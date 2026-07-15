#!/usr/bin/env ruby
# frozen_string_literal: true

# Runnable demo: invoice extraction, validation, and threshold-routed approval workflow.
#   bundle exec ruby examples/invoice_pipeline.rb
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

INVOICES = [
  "INVOICE INV-001 / PT Maju Jaya / 2026-07-01 / Total: Rp 1.500.000 / Office supplies",
  "INVOICE INV-002 / CV Mega Proyek / 2026-07-03 / Total: Rp 75.000.000 / Construction phase 2",
].freeze

Omnibot::Testing.fake!

class InvoiceExtractor < Omnibot::Agent
  instructions "Extract structured invoice fields from raw invoice text."
end

Omnibot::Testing::StubBuilder.new(InvoiceExtractor)
  .then_extract({ "vendor" => "PT Maju Jaya", "amount" => 1_500_000, "invoice_no" => "INV-001", "date" => "2026-07-01" })
  .then_extract({ "vendor" => "CV Mega Proyek", "amount" => 75_000_000, "invoice_no" => "INV-002", "date" => "2026-07-03" })

def validate!(fields)
  %i[vendor amount invoice_no date].each { |k| raise "missing #{k}" if fields[k].to_s.empty? && fields[k].to_i.zero? }
  raise "non-positive amount" unless fields[:amount].to_i.positive?
  fields
end

APPROVAL_THRESHOLD = 10_000_000

class ApprovalWorkflow < Omnibot::Workflow
  state :vendor, :amount, :invoice_no, :approved

  step :route do
    # routing happens via transitions below
  end

  step :auto_approve do
    state.approved = true
    reply "AUTO-APPROVED #{state.invoice_no} (#{state.vendor}, Rp#{state.amount})"
  end

  step :manual_review do
    if input.to_s == "approved"
      state.approved = true
      reply "MANUALLY APPROVED #{state.invoice_no} by reviewer"
    else
      handover! reason: "amount Rp#{state.amount} above Rp#{APPROVAL_THRESHOLD} threshold"
    end
  end

  transition from: :route, to: :auto_approve, if: -> { state.amount < APPROVAL_THRESHOLD }
  transition from: :route, to: :manual_review
  transition from: :auto_approve, to: :done
  transition from: :manual_review, to: :done
end

ledger = []
INVOICES.each do |raw|
  fields = validate!(InvoiceExtractor.extract(raw, schema: Class.new))
  run = ApprovalWorkflow.start(state: { vendor: fields[:vendor], amount: fields[:amount], invoice_no: fields[:invoice_no] })
  if run.status == "waiting_for_human"
    puts "⏸  #{fields[:invoice_no]} parked for human review"
    run = run.resume_from_human(input: "approved")
  end
  raise "#{fields[:invoice_no]} did not complete" unless run.status == "done"
  raise "#{fields[:invoice_no]} not approved" unless run.reload.state["approved"] == true
  ledger << "#{fields[:invoice_no]} | #{fields[:vendor]} | Rp#{fields[:amount]} | APPROVED"
end

raise "ledger should have 2 lines" unless ledger.length == 2
ledger.each { |line| puts "📒 #{line}" }
puts "✅ demo green"
