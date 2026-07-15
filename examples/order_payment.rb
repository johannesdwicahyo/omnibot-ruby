#!/usr/bin/env ruby
# frozen_string_literal: true

# Runnable demo: a durable e-commerce order-payment workflow on plain ActiveRecord.
#   bundle exec ruby examples/order_payment.rb
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
# ponytail: ActiveJob's :inline adapter can't run scheduled jobs at all
# (InlineAdapter#enqueue_at raises NotImplementedError), and schedule_poll
# always does `.set(wait: ...).perform_later`. Use :test + the same
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
class ReceiptAgent < Omnibot::Agent
  instructions "Extract payment details from the customer's receipt."
end
Omnibot::Testing::StubBuilder.new(ReceiptAgent)
  .then_extract({ "order_no" => "ORD-1042", "amount" => 250_000, "method" => "bank transfer" })

GATEWAY_RESULTS = [:pending, :pending, :paid]
def gateway_check = GATEWAY_RESULTS.shift

class OrderPaymentWorkflow < Omnibot::Workflow
  state :order_no, :amount, :method, :paid

  step :ask_for_receipt do
    reply "Thanks for your order! Please upload your payment receipt 🙏"
    wait_for_input
  end

  step :verify_receipt do
    receipt = ReceiptAgent.extract(input, schema: Class.new)
    state.order_no = receipt[:order_no]
    state.amount = receipt[:amount]
    state.method = receipt[:method]
    reply "Got it — Rp#{state.amount} via #{state.method} for #{state.order_no}. Confirming payment…"
  end

  step :watch_payment, poll: { every: 5, max_attempts: 5 } do
    status = gateway_check
    puts "  ⏱  gateway says: #{status} (attempt #{attempts})"
    if status == :pending
      reply "Payment still processing… (attempt #{attempts})"
      poll_again
    end
    state.paid = (status == :paid)
  end

  transition from: :ask_for_receipt, to: :verify_receipt
  transition from: :verify_receipt, to: :watch_payment
  transition from: :watch_payment, to: :done, if: -> { state.paid }
  transition from: :watch_payment, to: :failed
end

# ponytail: replies print via the notification subscriber above as they're
# emitted (`reply` instruments "omnibot.workflow.reply" synchronously) — no
# need to also walk run.replies here, that would just print each one twice.
puts "▶ customer places order ORD-1042"
run = OrderPaymentWorkflow.start
puts "  status: #{run.status} (durable — survives restarts; state in omnibot_workflow_runs)"

puts "▶ customer uploads the payment receipt"
run = OrderPaymentWorkflow.resume(run, input: "paid Rp250.000 by bank transfer for order ORD-1042, receipt attached")

puts "▶ waiting on the payment gateway"
2.times { jobs.perform_enqueued_jobs } # drains the remaining [pending, paid] poll ticks

puts "▶ final: #{run.reload.status} — #{run.state['order_no']} paid=#{run.state['paid']} → ship it 📦"
raise "demo failed!" unless run.status == "done" && run.state["paid"] == true && run.state["order_no"] == "ORD-1042"
puts "✅ demo green"
