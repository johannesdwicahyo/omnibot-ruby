#!/usr/bin/env ruby
# frozen_string_literal: true

# Runnable demo: sales qualification, lead capture, and durable booking workflow.
#   bundle exec ruby examples/sales_bot.rb
# No API keys needed — agents run on Omnibot's fake LLM.

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

Omnibot::Testing.fake!

# Phase 1: qualification by extraction (no conversation)
puts "▶ Phase 1: Qualification extract"

class QualifierAgent < Omnibot::Agent
  instructions "Extract sales qualification data from the prospect's message."
end

Omnibot::Testing::StubBuilder.new(QualifierAgent)
  .then_extract({ "need" => "POS system", "budget" => 2_000_000, "timeline" => "asap" })

lead = QualifierAgent.extract(
  "Hi, we run 3 stores and need a POS system, budget around 2 juta per month, ideally starting ASAP",
  schema: Class.new
)
raise "qualification failed" unless lead == { need: "POS system", budget: 2_000_000, timeline: "asap" }
puts "  ✓ lead qualified: #{lead.inspect}"

# Phase 2: sales agent captures the lead (real tool body runs)
puts "\n▶ Phase 2: Lead capture"

module Demo
  class << self
    attr_accessor :lead
  end
end

class SalesBot < Omnibot::Agent
  instructions "You are a friendly sales assistant for MochiPOS."
  tool :capture_lead, "Save the prospect's contact details" do |name:, phone:|
    Demo.lead = { name: name, phone: phone }
    "Saved lead #{name}"
  end
end

Omnibot::Testing::StubBuilder.new(SalesBot)
  .to_call_tool(:capture_lead, name: "Budi", phone: "081234567890")
  .then_reply("Thanks Budi! Let's get you booked for a demo.")

r = SalesBot.run("I'm Budi, 081234567890 — I'd like a demo")
raise "lead not captured" unless Demo.lead == { name: "Budi", phone: "081234567890" }
puts "  ✓ lead captured: #{Demo.lead.inspect}"

# Phase 3: the conversation becomes a durable process
puts "\n▶ Phase 3: Durable booking workflow"

class BookingWorkflow < Omnibot::Workflow
  state :slot

  step :offer_slots do
    reply "We have demo slots: Tue 10:00 or Wed 14:00 — which works?"
    wait_for_input
  end

  step :confirm do
    state.slot = input
    reply "Booked! See you #{state.slot} 🎉"
  end

  transition from: :offer_slots, to: :confirm
  transition from: :confirm, to: :done
end

run = BookingWorkflow.start
raise "should wait for the prospect" unless run.status == "waiting_for_input"
raise "slots not offered" unless run.replies.first.include?("Tue 10:00")
puts "  ✓ workflow waiting for input, slots offered"

run = BookingWorkflow.resume(run, input: "Wed 14:00")
raise "booking not completed" unless run.status == "done"
raise "slot not persisted" unless run.reload.state["slot"] == "Wed 14:00"
raise "confirmation missing" unless run.replies.first.include?("Booked")
puts "  ✓ booking completed: #{run.state.inspect}"

puts "\n✅ demo green"
