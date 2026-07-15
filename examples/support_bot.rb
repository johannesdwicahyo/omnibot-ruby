#!/usr/bin/env ruby
# frozen_string_literal: true

# Runnable demo: a support chatbot with fast-path, docs search, and escalation.
#   bundle exec ruby examples/support_bot.rb
# No API keys needed — the agent step runs on Omnibot's fake LLM.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "omnibot"

# Demo state holder
module Demo
  class << self
    attr_accessor :escalation, :searched
  end
end

# Documentation database
DOCS = {
  "reset password" => "Go to Settings → Security → Reset.",
  "billing cycle" => "Invoices are issued on the 1st."
}

# Agent definition
class SupportBot < Omnibot::Agent
  instructions "You are the support assistant for Acme Cloud. Use the docs tool before answering technical questions."
  max_turns 4

  fast_path do |message, _context|
    reply "Halo! 👋 Menu: 1) Reset password 2) Billing 3) Talk to human" if message.match?(/\A(hi|halo|hai|hello)\b/i)
  end

  tool :search_docs, "Search the product documentation" do |query:|
    Demo.searched = query
    DOCS.select { |title, _| query.downcase.split.any? { |w| title.include?(w) } }
        .map { |title, body| "[#{title}] #{body}" }
        .join("\n").then { |r| r.empty? ? "No docs found." : r }
  end

  tool :escalate, "Escalate to a human agent" do |reason:|
    Demo.escalation = reason
    "Escalated: #{reason}"
  end
end

# Set up fake testing
Omnibot::Testing.fake!
Omnibot::Testing::StubBuilder.new(SupportBot)
  .to_call_tool(:search_docs, query: "reset password")
  .then_reply("To reset your password: Settings → Security → Reset. Anything else?")
  .to_call_tool(:escalate, reason: "customer requests a human agent")
  .then_reply("I'm connecting you to a human agent now 🙏")

# Turn loop with transcript
history = []
say = lambda do |text|
  puts "👤 #{text}"
  result = SupportBot.run(text, history: history)
  puts "🤖 #{result.text}"
  history << { role: "user", content: text } << { role: "assistant", content: result.text }
  result
end

# Turn 1: fast-path
r1 = say.call("halo")
raise "turn 1 should fast-path" unless r1.fast_path? && r1.usage.input_tokens.zero?
raise "turn 1 menu missing" unless r1.text.include?("Menu")

# Turn 2: search docs
r2 = say.call("How do I reset my password?")
raise "docs tool did not run" unless Demo.searched == "reset password"
raise "turn 2 tool call missing" unless r2.tool_calls.map(&:name) == ["search_docs"]
raise "turn 2 reply wrong" unless r2.text.include?("Settings → Security")

# Turn 3: escalate
r3 = say.call("I want to talk to a human please")
raise "escalation not recorded" unless Demo.escalation == "customer requests a human agent"
raise "history should thread 6 entries" unless history.length == 6

puts "✅ demo green"
