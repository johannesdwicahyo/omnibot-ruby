#!/usr/bin/env ruby
# frozen_string_literal: true

# Runnable demo: a durable deposit-check workflow on plain ActiveRecord.
#   bundle exec ruby examples/deposit_check.rb
# No API keys needed — the agent step runs on Omnibot's fake LLM.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "omnibot"
require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = nil
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :omnibot_workflow_runs do |t|
    t.string :type, null: false
    t.string :status, null: false
    t.string :current_step
    t.json :state, default: {}
    t.integer :attempts, default: 0, null: false
    t.datetime :step_entered_at
    t.integer :timer_token, default: 0, null: false
    t.string :ref_type
    t.bigint :ref_id
    t.text :error
    t.timestamps
  end
end

require "active_job/test_helper"
# ponytail: the brief assumed :inline "ignores wait: — fine for a demo", but
# InlineAdapter#enqueue_at (activejob 8.1.3, and every version we've seen)
# just raises NotImplementedError — it only ever implemented immediate
# `enqueue`. schedule_poll always does `.set(wait: ...).perform_later`, so
# inline can't run a poll step at all. Use :test + the same
# ActiveJob::TestHelper#perform_enqueued_jobs the suite's own poll specs use
# (spec/omnibot/workflow_poll_spec.rb) to drain ticks deterministically —
# still no real clock, still a demo, just the adapter that actually works.
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(IO::NULL)
jobs = Object.new.extend(ActiveJob::TestHelper)

# Deliver background replies (poll/timeout ticks) — one subscriber, app-side.
ActiveSupport::Notifications.subscribe("omnibot.workflow.reply") do |event|
  puts "  🤖 #{event.payload[:text]}"
end

Omnibot::Testing.fake!
class ProofAgent < Omnibot::Agent
  instructions "Extract deposit details from the receipt."
end
Omnibot::Testing::StubBuilder.new(ProofAgent).then_extract({ "amount" => 50_000, "bank" => "BCA" })

GATEWAY_RESULTS = [:pending, :pending, :paid]
def gateway_check = GATEWAY_RESULTS.shift

class DepositCheckWorkflow < Omnibot::Workflow
  state :amount, :bank, :paid

  step :ask_for_proof do
    reply "Please upload your transfer receipt 🙏"
    wait_for_input
  end

  step :extract_proof do
    proof = ProofAgent.extract(input, schema: Class.new)
    state.amount = proof[:amount]
    state.bank = proof[:bank]
    reply "Got it — Rp#{state.amount} via #{state.bank}. Checking with the gateway…"
  end

  step :watch_gateway, poll: { every: 5, max_attempts: 5 } do
    status = gateway_check
    puts "  ⏱  gateway says: #{status} (attempt #{attempts})"
    if status == :pending
      reply "Still checking with the gateway… (attempt #{attempts})"
      poll_again
    end
    state.paid = (status == :paid)
  end

  transition from: :ask_for_proof, to: :extract_proof
  transition from: :extract_proof, to: :watch_gateway
  transition from: :watch_gateway, to: :done, if: -> { state.paid }
  transition from: :watch_gateway, to: :failed
end

# ponytail: replies print via the notification subscriber above as they're
# emitted (`reply` instruments "omnibot.workflow.reply" synchronously) — no
# need to also walk run.replies here, that would just print each one twice.
puts "▶ start"
run = DepositCheckWorkflow.start
puts "  status: #{run.status} (durable — survives restarts; state in omnibot_workflow_runs)"

puts "▶ customer sends the receipt"
run = DepositCheckWorkflow.resume(run, input: "transfer 50rb via BCA, receipt attached")

puts "▶ waiting on the payment gateway"
2.times { jobs.perform_enqueued_jobs } # drains the remaining [pending, paid] poll ticks

puts "▶ final: #{run.reload.status} — paid=#{run.state['paid']}"
raise "demo failed!" unless run.status == "done" && run.state["paid"] == true
puts "✅ demo green"
