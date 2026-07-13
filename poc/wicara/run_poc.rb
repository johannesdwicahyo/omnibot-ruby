# frozen_string_literal: true

# Side-by-side harness: drives the same 15-message conversation through
# wicara's Python/LangGraph service and the Ruby omnibot mirror, then writes
# poc/wicara/report.md with replies, tool calls, citations, tokens, latency,
# an LLM judge verdict per turn, and hard parity checks.
#
# Usage: cd poc/wicara && WICARA_INTERNAL_TOKEN=... OPENAI_API_KEY=... bundle exec ruby run_poc.rb
# Exit codes: 2 = precondition failure (remedy printed); 1 = hard check
# failed or a Ruby exception occurred; 0 = go.

require "set"
require "yaml"
require "securerandom"
require_relative "db"
require_relative "python_client"
require_relative "wicara_agent"

WICARA_DB_URL = ENV.fetch("WICARA_DB_URL", "postgres://localhost:5432/wicara_development")
WICARA_AI_URL = ENV.fetch("WICARA_AI_URL", "http://localhost:8000")
MODEL = "gpt-4o-mini"
HISTORY_WINDOW = 12

def fail_precondition(message)
  puts "PRECONDITION FAILED"
  puts message
  exit 2
end

# --- 1. Preconditions ---

token = ENV["WICARA_INTERNAL_TOKEN"].to_s
fail_precondition(<<~MSG) if token.empty?
  WICARA_INTERNAL_TOKEN is not set.
  Set it to the same token value the wicara AI service is running with, e.g.:
    export WICARA_INTERNAL_TOKEN=your-shared-token
MSG

openai_key = ENV["OPENAI_API_KEY"].to_s
fail_precondition(<<~MSG) if openai_key.empty?
  OPENAI_API_KEY is not set.
  Export a valid key before running the harness (needed for the Ruby agent and the judge):
    export OPENAI_API_KEY=sk-...
MSG

db = begin
  WicaraPoc::DB.new(WICARA_DB_URL)
rescue StandardError => e
  fail_precondition("Could not connect to WICARA_DB_URL (#{WICARA_DB_URL}): #{e.class}: #{e.message}")
end

bot = begin
  db.load_bot(slug: ENV["WICARA_BOT_SLUG"])
rescue StandardError => e
  fail_precondition("DB query failed while loading the bot: #{e.class}: #{e.message}")
end
fail_precondition(<<~MSG) if bot.nil?
  No bot with a non-empty config->kb_ids was found in #{WICARA_DB_URL}.
  Seed wicara dev data (in the wicara session) or set WICARA_BOT_SLUG to an existing bot's slug.
MSG

python = WicaraPoc::PythonClient.new(url: WICARA_AI_URL, token: token)
fail_precondition(<<~MSG) unless python.health
  wicara Python AI service health check failed (GET #{WICARA_AI_URL}/v1/health).
  Start it in your wicara session with the fake embedder enabled:
    cd ~/Projects/2026/wicara/ai && USE_FAKE_EMBEDDER=true .venv/bin/uvicorn app.main:app --port 8000
  (also set AI_DATABASE_URL, AI_REDIS_URL, WICARA_INTERNAL_TOKEN, OPENAI_API_KEY in its env)
MSG

# --- Live path only from here: configure RubyLLM once, build the agent ---
RubyLLM.configure { |c| c.openai_api_key = openai_key }

agent_klass = WicaraPoc.build_agent(bot: bot, db: db)
messages = YAML.load_file(File.join(__dir__, "messages.yml")).map { |m| m.transform_keys(&:to_sym) }

# --- 2. Run: one shared conversation per engine ---

cid = SecureRandom.uuid
python_history = []
ruby_history = []
rows = []
ruby_exception_count = 0

window = ->(hist) { hist.last(HISTORY_WINDOW) }

messages.each do |msg|
  text = msg[:text]
  row = { label: msg[:label], text: text, expect: msg[:expect] }

  begin
    t0 = Time.now
    presp = python.chat(workspace_id: bot[:workspace_id], bot_id: bot[:id], conversation_id: cid,
                         user_message: text, history: window.call(python_history))
    row[:python] = {
      reply: presp[:reply_text],
      tool_calls: presp[:tool_calls] || [],
      citations: presp[:citations] || [],
      usage: presp[:usage] || {},
      handover: presp[:handover],
      latency_ms: ((Time.now - t0) * 1000).round
    }
    python_history << { role: "user", content: text }
    python_history << { role: "assistant", content: presp[:reply_text].to_s }
  rescue StandardError => e
    row[:python] = { error: "#{e.class}: #{e.message}" }
    python_history << { role: "user", content: text }
  end

  begin
    t0 = Time.now
    result = agent_klass.run(text, history: window.call(ruby_history), context: { conversation_id: cid })
    latency_ms = ((Time.now - t0) * 1000).round
    handover = WicaraPoc.last_handover
    kb_rows = WicaraPoc.last_kb_results
    WicaraPoc.last_handover = nil
    WicaraPoc.last_kb_results = nil
    row[:ruby] = {
      reply: result.text,
      tool_calls: result.tool_calls.map { |tc| { name: tc.name, arguments: tc.arguments } },
      citations: (kb_rows || []).map { |r| { kb_document_id: r[:kb_document_id], chunk_index: r[:chunk_index], score: r[:score] } },
      usage: { prompt_tokens: result.usage.input_tokens, completion_tokens: result.usage.output_tokens },
      handover: handover,
      fast_path: result.fast_path?,
      latency_ms: latency_ms
    }
    ruby_history << { role: :user, content: text }
    ruby_history << { role: :assistant, content: result.text.to_s }
  rescue StandardError => e
    ruby_exception_count += 1
    row[:ruby] = { error: "#{e.class}: #{e.message}" }
    ruby_history << { role: :user, content: text }
  end

  rows << row
end

# --- 3. Hard parity checks ---

checks = []
add_check = ->(name, status, detail) { checks << { name: name, status: status, detail: detail } }

# (a) greeting fast path
greeting_rows = rows.select { |r| r[:expect] == "greeting_fast_path" }
if bot[:config]["greeting_menu"].to_s.empty?
  add_check.call("greeting_fast_path", "SKIPPED", "bot has no greeting_menu configured")
else
  ok = greeting_rows.all? { |r| r.dig(:python, :usage, :model) == "fast_path" && r.dig(:ruby, :fast_path) == true }
  detail = greeting_rows.map { |r| "#{r[:text].inspect}: python=#{r.dig(:python, :usage, :model) == 'fast_path'} ruby=#{r.dig(:ruby, :fast_path) == true}" }.join("; ")
  add_check.call("greeting_fast_path", ok ? "PASS" : "FAIL", detail)
end

# (b) KB citations: ruby's cited set must be subset-or-equal of python's
kb_rows = rows.select { |r| r[:expect] == "kb_answer" }
kb_ok = true
kb_detail = kb_rows.map do |r|
  if r.dig(:python, :error) || r.dig(:ruby, :error)
    "#{r[:text].inspect}: ERROR (see message section)"
  else
    p_set = (r.dig(:python, :citations) || []).map { |c| [c[:kb_document_id], c[:chunk_index]] }.to_set
    r_set = (r.dig(:ruby, :citations) || []).map { |c| [c[:kb_document_id], c[:chunk_index]] }.to_set
    relation =
      if r_set == p_set
        "EXACT"
      elsif r_set.subset?(p_set)
        "SUBSET"
      else
        kb_ok = false
        "MISMATCH"
      end
    "#{r[:text].inspect}: #{relation} (python=#{p_set.size} ruby=#{r_set.size})"
  end
end.join("; ")
add_check.call("kb_citations", kb_ok ? "PASS" : "FAIL", kb_detail)

# (c) handover
handover_row = rows.find { |r| r[:expect] == "handover" }
if handover_row
  p_req = handover_row.dig(:python, :handover, :requested) == true
  r_req = handover_row.dig(:ruby, :handover, :requested) == true
  add_check.call("handover", (p_req && r_req) ? "PASS" : "FAIL", "python_requested=#{p_req} ruby_requested=#{r_req}")
end

# (d) anger backstop: SKIPPED if threshold is off, else PASS iff both engines
# AGREE per anger entry (both tripped, or both not) — parity, not absolute behavior.
threshold = bot[:config]["handover_on_anger_threshold"].to_i
if threshold <= 0
  add_check.call("anger_handover", "SKIPPED", "handover_on_anger_threshold is 0")
else
  anger_rows = rows.select { |r| r[:expect] == "anger_handover" }
  any_tripped = false
  all_agree = true
  detail = anger_rows.map do |r|
    p_req = r.dig(:python, :handover, :requested) == true
    r_req = r.dig(:ruby, :handover, :requested) == true
    any_tripped ||= p_req || r_req
    all_agree &&= (p_req == r_req)
    "#{r[:text].inspect}: python=#{p_req} ruby=#{r_req}"
  end.join("; ")
  if all_agree && !any_tripped && threshold > 2
    detail += " (threshold #{threshold} > battery's 2 profane messages — neither engine expected to trip)"
  end
  add_check.call("anger_handover", all_agree ? "PASS" : "FAIL", detail)
end

# --- 4. Judge: one call per non-fast-path pair ---

JUDGE_SYSTEM = "You compare two customer-support replies to the same user message. " \
               "Answer YES if they convey an equivalent answer, PARTIAL if they overlap but differ materially, " \
               "NO otherwise. First word = verdict, then one sentence why.".freeze

judged = []
rows.each do |r|
  next if r.dig(:python, :error) || r.dig(:ruby, :error)
  next if r.dig(:python, :usage, :model) == "fast_path" || r.dig(:ruby, :fast_path) == true

  user_prompt = "User message: #{r[:text]}\n\nA: #{r.dig(:python, :reply)}\n\nB: #{r.dig(:ruby, :reply)}"

  begin
    response = RubyLLM.chat(model: MODEL).with_instructions(JUDGE_SYSTEM).ask(user_prompt)
    content = response.content.to_s.strip
    verdict = content.split(/\s+/).first.to_s.upcase.gsub(/[^A-Z]/, "")
    verdict = "NO" unless %w[YES PARTIAL NO].include?(verdict)
    r[:judge] = { verdict: verdict, reason: content }
  rescue StandardError => e
    r[:judge] = { verdict: "ERROR", reason: "#{e.class}: #{e.message}" }
  end
  judged << r
end

# --- 5. report.md ---

lines = []
lines << "# Wicara Engine-Swap PoC Report"
lines << ""
lines << "- Date: #{Time.now.utc.iso8601}"
lines << "- Bot: id=#{bot[:id]} slug=#{ENV['WICARA_BOT_SLUG'] || '(auto-selected)'}"
lines << "- Model: #{MODEL}"
lines << "- Messages: #{rows.length}"
lines << ""
lines << "## Messages"
lines << ""

rows.each_with_index do |r, i|
  lines << "### #{i + 1}. #{r[:label]} (expect: #{r[:expect]})"
  lines << ""
  lines << "**User:** #{r[:text]}"
  lines << ""
  lines << "**Python:** #{r.dig(:python, :error) ? "ERROR — #{r[:python][:error]}" : r.dig(:python, :reply)}"
  lines << ""
  lines << "**Ruby:** #{r.dig(:ruby, :error) ? "ERROR — #{r[:ruby][:error]}" : r.dig(:ruby, :reply)}"
  lines << ""
  lines << "| | Python | Ruby |"
  lines << "|---|---|---|"
  lines << "| tool_calls | #{(r.dig(:python, :tool_calls) || []).map { |t| t[:name] }.join(', ')} | #{(r.dig(:ruby, :tool_calls) || []).map { |t| t[:name] }.join(', ')} |"
  lines << "| citations | #{(r.dig(:python, :citations) || []).map { |c| "[#{c[:kb_document_id]}:#{c[:chunk_index]}]" }.join(', ')} | #{(r.dig(:ruby, :citations) || []).map { |c| "[#{c[:kb_document_id]}:#{c[:chunk_index]}]" }.join(', ')} |"
  lines << "| tokens (prompt/completion) | #{r.dig(:python, :usage, :prompt_tokens)}/#{r.dig(:python, :usage, :completion_tokens)} | #{r.dig(:ruby, :usage, :prompt_tokens)}/#{r.dig(:ruby, :usage, :completion_tokens)} |"
  lines << "| latency ms | #{r.dig(:python, :latency_ms)} | #{r.dig(:ruby, :latency_ms)} |"
  lines << ""
  lines << (r[:judge] ? "**Judge:** #{r[:judge][:verdict]} — #{r[:judge][:reason]}" : "**Judge:** (skipped — fast path or error)")
  lines << ""
end

lines << "## Hard Parity Checks"
lines << ""
lines << "| Check | Status | Detail |"
lines << "|---|---|---|"
checks.each { |c| lines << "| #{c[:name]} | #{c[:status]} | #{c[:detail]} |" }
lines << ""

tally = judged.group_by { |r| r[:judge][:verdict] }.transform_values(&:count)
total_judged = judged.length
positive = (tally["YES"] || 0) + (tally["PARTIAL"] || 0)
judge_pct = total_judged.zero? ? 0.0 : (positive.to_f / total_judged * 100).round(1)

lines << "## Judge Tally"
lines << ""
lines << "- YES: #{tally['YES'] || 0}"
lines << "- PARTIAL: #{tally['PARTIAL'] || 0}"
lines << "- NO: #{tally['NO'] || 0}"
lines << "- ERROR: #{tally['ERROR'] || 0}"
lines << "- Total judged: #{total_judged}"
lines << "- YES+PARTIAL rate: #{judge_pct}%"
lines << ""

python_tokens = rows.sum { |r| (r.dig(:python, :usage, :prompt_tokens) || 0) + (r.dig(:python, :usage, :completion_tokens) || 0) }
ruby_tokens = rows.sum { |r| (r.dig(:ruby, :usage, :prompt_tokens) || 0) + (r.dig(:ruby, :usage, :completion_tokens) || 0) }
python_latency = rows.sum { |r| r.dig(:python, :latency_ms) || 0 }
ruby_latency = rows.sum { |r| r.dig(:ruby, :latency_ms) || 0 }
token_ratio = python_tokens.zero? ? nil : (ruby_tokens.to_f / python_tokens).round(2)
latency_ratio = python_latency.zero? ? nil : (ruby_latency.to_f / python_latency).round(2)

lines << "## Totals"
lines << ""
lines << "- Python tokens: #{python_tokens}, Ruby tokens: #{ruby_tokens}, ratio (ruby/python): #{token_ratio || 'n/a'}"
lines << "- Python latency ms: #{python_latency}, Ruby latency ms: #{ruby_latency}, ratio (ruby/python): #{latency_ratio || 'n/a'}"
lines << ""

lines << "## Documented Asymmetries"
lines << ""
lines << "1. **capture_lead**: Python's `capture_lead` really POSTs to Rails `/internal/contacts/upsert` (may create a dev contact row); the Ruby stub returns a canned success string with no HTTP call."
lines << "2. **Turn-limit semantics**: Python `ITERATION_CAP=4` counts LLM calls; Ruby `max_turns 4` counts tool executions (each parallel tool call in a round counts separately) — not the same quantity, so the two can diverge on multi-tool turns."
lines << "3. **Anger counter**: both sides use an in-memory, single-process `Hash`/dict counter with no TTL or persistence; a process restart resets it, and it isn't shared across processes."
lines << ""

hard_checks_pass = checks.reject { |c| c[:status] == "SKIPPED" }.all? { |c| c[:status] == "PASS" }
zero_exceptions = ruby_exception_count.zero?
judge_pass = judge_pct >= 80.0
tokens_within_2x = token_ratio.nil? || token_ratio.between?(0.5, 2.0)
latency_within_2x = latency_ratio.nil? || latency_ratio.between?(0.5, 2.0)
overall = hard_checks_pass && zero_exceptions

lines << "## Success Criteria"
lines << ""
lines << "- All hard checks pass (non-SKIPPED): #{hard_checks_pass ? 'PASS' : 'FAIL'}"
lines << "- Judge >= 80% YES/PARTIAL: #{judge_pass ? 'PASS' : 'FAIL'} (#{judge_pct}%)"
lines << "- Zero Ruby exceptions: #{zero_exceptions ? 'PASS' : 'FAIL'} (#{ruby_exception_count} exceptions)"
lines << "- Tokens within 2x: #{tokens_within_2x ? 'PASS' : 'FAIL'} (ratio #{token_ratio || 'n/a'})"
lines << "- Latency within 2x: #{latency_within_2x ? 'PASS' : 'FAIL'} (ratio #{latency_ratio || 'n/a'})"
lines << ""
lines << "**Overall: #{overall ? 'GO' : 'NO-GO'}** (judge % and the 2x token/latency ratios are reported for human review, not gating.)"

report_path = File.join(__dir__, "report.md")
File.write(report_path, lines.join("\n"))

# --- 6. stdout summary + exit code ---

puts "wrote #{report_path}"
checks.each { |c| puts "[#{c[:status]}] #{c[:name]}: #{c[:detail]}" }
puts "ruby_exceptions=#{ruby_exception_count}"
puts "judge: #{judge_pct}% YES/PARTIAL (#{total_judged} judged)"
puts overall ? "OVERALL: GO" : "OVERALL: NO-GO"

exit(overall ? 0 : 1)
