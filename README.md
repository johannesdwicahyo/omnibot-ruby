# omnibot-ruby

Rails-first LLM agents for Ruby.

## Why

`omnibot-ruby` is a Rails-idiomatic agent framework built on [`ruby_llm`](https://github.com/crmne/ruby_llm) — a class DSL for bounded tool-calling agents that lives in your Rails app, not a Python sidecar you have to deploy, proxy, and keep in sync. It ships two primitives: **Agent** (a bounded tool-calling loop with fast paths, structured extraction, and streaming) and **Workflow** (v0.2 — a durable, ActiveRecord-checkpointed graph engine for multi-step conversations with human handover, so long-running flows survive restarts without a Redis checkpointer). Everything runs in-process, which means token streaming to ActionCable/Turbo is a callback away instead of blocked behind an HTTP hop.

## Install

```bash
bundle add omnibot-ruby
rails g omnibot:install
```

The install generator writes `config/initializers/omnibot.rb`, where you set your default model:

```ruby
Omnibot.configure do |config|
  config.default_model = "gpt-4o-mini"
  # config.on_tool_error = :capture  # or :raise
end
```

Scaffold an agent with:

```bash
rails g omnibot:agent Support
```

This creates `app/agents/support_agent.rb` and a matching spec in `spec/agents/`.

## Quick start

```ruby
class SupportAgent < Omnibot::Agent
  model "claude-sonnet-5"                                # any ruby_llm model string
  instructions "You help customers of {{company}}."      # {{var}} interpolates from context
  max_turns 3

  tool :lookup_order, "Find an order" do |order_id:|
    "order #{order_id}: shipped"
  end
end

result = SupportAgent.run("where is order #123?",
  history: conversation.recent_messages,   # app-owned, app-windowed
  context: { company: "Wokku" })

result.text          # => "Order 123 is shipped!"
result.tool_calls     # => [#<struct Omnibot::ToolCallRecord name="lookup_order", arguments={:order_id=>123}>]
result.usage.input_tokens
```

Semantics worth knowing:

- The loop is: send → execute tool calls → append results → repeat, up to `max_turns`. On the final turn, tools are unbound so the model is forced to answer instead of looping forever. `max_turns` bounds the number of tool executions in a run (parallel tool calls each count) — not conversation rounds.
- `instructions` support `{{var}}` interpolation from `context`; a missing variable raises `KeyError`.
- `history` is a plain array of `{ role:, content: }` hashes (or anything that responds to `#role`/`#content`) — the gem never persists conversations itself.
- A custom `Omnibot.chat_factory` lambda must accept extra kwargs (e.g. `->(model:, **) { ... }`) — Agent always calls it with `agent_class:` in addition to `model:`.
- Per-agent factories (v0.2.1): declare `chat_factory ->(model:, **) { RubyLLM.chat(model: model).with_temperature(0.9) }` inside an agent class to customize chat construction for that agent only (inherited by subclasses; overridable). Precedence: `Omnibot::Testing.fake!` > class-level `chat_factory` > global `Omnibot.chat_factory` — so specs stay offline even for agents with custom factories.
- Block-tool params are always JSON type `"string"` — models send `"123"`, not `123`. Declare param types via class-form tools (`param :n, type: "integer"`) when types matter.
- Class-form tools must declare `param` explicitly — the wrapper that adds error capture shadows `#execute`'s signature, so ruby_llm's automatic param inference doesn't see your keyword args:

  ```ruby
  class AddTool < Omnibot::Tool
    description "Adds two numbers"
    param :a, desc: "First"
    param :b, desc: "Second"

    def execute(a:, b:) = a + b
  end

  class SupportAgent < Omnibot::Agent
    tool AddTool
  end
  ```

## What can you build

**A support chatbot with fast paths, a docs tool, and escalation** — [`examples/support_bot.rb`](examples/support_bot.rb):

```ruby
  fast_path do |message, _context|
    reply "Halo! 👋 Menu: 1) Reset password 2) Billing 3) Talk to human" if message.match?(/\A(hi|halo|hai|hello)\b/i)
  end

  tool :search_docs, "Search the product documentation" do |query:|
    Demo.searched = query
    DOCS.select { |title, _| query.downcase.split.any? { |w| title.include?(w) } }
        .map { |title, body| "[#{title}] #{body}" }
        .join("\n").then { |r| r.empty? ? "No docs found." : r }
  end
```

**A sales assistant that qualifies leads, captures contacts, and turns the conversation into a durable booking** — [`examples/sales_bot.rb`](examples/sales_bot.rb):

```ruby
  step :offer_slots do
    reply "We have demo slots: Tue 10:00 or Wed 14:00 — which works?"
    wait_for_input
  end

  step :confirm do
    state.slot = input
    reply "Booked! See you #{state.slot} 🎉"
  end
```

**An invoice approval pipeline with zero chat — extract, validate, and route on a threshold** — [`examples/invoice_pipeline.rb`](examples/invoice_pipeline.rb):

```ruby
  .then_extract({ "vendor" => "PT Maju Jaya", "amount" => 1_500_000, "invoice_no" => "INV-001", "date" => "2026-07-01" })
  .then_extract({ "vendor" => "CV Mega Proyek", "amount" => 75_000_000, "invoice_no" => "INV-002", "date" => "2026-07-03" })

def validate!(fields)
  %i[vendor amount invoice_no date].each { |k| raise "missing #{k}" if fields[k].to_s.empty? && fields[k].to_i.zero? }
  raise "non-positive amount" unless fields[:amount].to_i.positive?
  fields
end

APPROVAL_THRESHOLD = 10_000_000
```

**An order-payment workflow that durably polls an external payment gateway** — [`examples/order_payment.rb`](examples/order_payment.rb):

```ruby
  step :watch_payment, poll: { every: 5, max_attempts: 5 } do
    status = gateway_check
    puts "  ⏱  gateway says: #{status} (attempt #{attempts})"
    if status == :pending
      reply "Payment still processing… (attempt #{attempts})"
      poll_again
    end
    state.paid = (status == :paid)
  end
```

All examples run offline in seconds: `bundle exec ruby examples/support_bot.rb` — no API key needed.

## Fast paths

Fast paths run in declaration order *before* any LLM call. Call `reply(text)` to short-circuit with zero token usage; return `nil` (or don't call `reply`) to fall through to the next fast path, and eventually to the LLM. Override `tools_for(context)` to gate which tools are attached per run.

```ruby
class SupportAgent < Omnibot::Agent
  instructions "support"

  fast_path do |message, _context|
    reply("Halo! Ada yang bisa dibantu?") if message.match?(/\A(hi|halo|hai)\b/i)
  end

  fast_path do |_message, context|
    reply("VIP line") if context[:vip]
  end

  tool(:escalate, "Escalate") { |**| "escalated" }
  tool(:lookup, "Lookup")     { |**| "found" }

  def tools_for(context)
    context[:angry] ? self.class.tools.reject { |t| t.new.name == "escalate" } : super
  end
end

result = SupportAgent.run("halo kak")
result.text         # => "Halo! Ada yang bisa dibantu?"
result.fast_path?   # => true
result.usage.input_tokens # => 0
```

## Structured extraction

`Agent.extract(input, schema:)` runs a single-shot structured extraction. Pass a [`RubyLLM::Schema`](https://github.com/crmne/ruby_llm) subclass describing the shape you want; on invalid JSON, omnibot automatically retries once with a repair prompt before raising `Omnibot::ExtractionError`.

```ruby
class PaymentReceipt < RubyLLM::Schema
  string :method
  integer :amount
end

class ReceiptAgent < Omnibot::Agent
  instructions "Extract the payment method and amount from the customer's message."
end

result = ReceiptAgent.extract("paid Rp250.000 by bank transfer", schema: PaymentReceipt)
result # => { amount: 250_000, method: "bank transfer" }
```

Note for testing: `Omnibot::Testing`'s fake chat ignores whatever you pass as `schema:` — it just parses the scripted reply as JSON (or passes a scripted Hash straight through via `then_extract`). Schema-driven provider-side structured output only kicks in against a real LLM.

## Streaming

Pass `stream:` to `run` and it's called with each response chunk as a plain `String`, as it arrives:

```ruby
chunks = []
result = SupportAgent.run("hi", stream: ->(chunk) { chunks << chunk })
chunks.join    # => the full reply text, assembled from chunks
result.text    # => the same full text once the run completes
```

Fast-path replies are never streamed — they short-circuit before any LLM call, so `stream` is simply not invoked for that run.

Broadcasting to the browser is a plain app-side recipe, not framework code:

```ruby
result = SupportAgent.run(message.body,
  context: { company: current_account.name },
  stream: ->(chunk) {
    ActionCable.server.broadcast("conversation_#{conversation.id}", chunk: chunk)
  })
```

## Testing your agents

`Omnibot::Testing.fake!` swaps in a deterministic scripted fake LLM so specs never hit a real provider. Script tool calls and replies with `stub_agent`, include `Omnibot::Testing::Helpers` for the `stub_agent` method, and reset after each example.

```ruby
RSpec.describe SupportAgent do
  include Omnibot::Testing::Helpers

  before { Omnibot::Testing.fake! }
  after  { Omnibot::Testing.reset! }

  it "looks up the order and replies" do
    stub_agent(SupportAgent)
      .to_call_tool(:lookup_order, order_id: 123)
      .then_reply("Order 123 is shipped!")

    result = SupportAgent.run("where is order 123?", context: { company: "Wokku" })

    expect(result.text).to eq("Order 123 is shipped!")
    expect(result.tool_calls.map(&:name)).to eq(["lookup_order"])
  end
end
```

The fake replays your script in order: `to_call_tool` asserts a tool is called and actually executes it (so bugs in your tool body still surface), `then_reply` ends the turn with a text reply, and `then_extract` ends it with a Hash for `Agent.extract` specs. If the script runs out, unscripted calls get a default `"(fake) <message>"` reply so runaway loops fail loudly instead of hanging. Class-form tools are plain Ruby objects — unit-test them directly, no fake required.

## Durable workflows

`Omnibot::Workflow` is a checkpoint-per-step graph engine for multi-step conversations that must survive a restart between messages: steps are nodes, transitions are edges, state persists as jsonb on a gem-owned `omnibot_workflow_runs` table. No Redis checkpointer, no graph compilation, no sidecar — it's ActiveRecord and ActiveJob, which your Rails app already has.

```bash
rails g omnibot:install       # also creates the omnibot_workflow_runs migration (skipped if it exists)
rails g omnibot:workflow OrderPayment
```

```ruby
class OrderPaymentWorkflow < Omnibot::Workflow
  state :amount, :method, :paid

  step :ask_for_receipt do
    reply "Thanks for your order! Please upload your payment receipt 🙏"
    wait_for_input                              # checkpoint: pause and persist; resumes on the next message
  end

  step :verify_receipt do
    receipt = ReceiptAgent.extract(input, schema: Class.new)   # input = what resume() received
    state.amount = receipt[:amount]
    state.method = receipt[:method]
    reply "Got it — Rp#{state.amount} via #{state.method}. Confirming payment…"
  end

  step :watch_payment, poll: { every: 5, max_attempts: 5 } do
    status = gateway_check
    if status == :pending
      reply "Payment still processing… (attempt #{attempts})"
      poll_again                                # schedule the next tick, stop this one
    end
    state.paid = (status == :paid)
  end

  transition from: :ask_for_receipt, to: :verify_receipt
  transition from: :verify_receipt, to: :watch_payment
  transition from: :watch_payment, to: :done, if: -> { state.paid }
  transition from: :watch_payment, to: :failed
end

run = OrderPaymentWorkflow.start
run.status          # => "waiting_for_input"
run.replies         # => ["Thanks for your order! Please upload your payment receipt 🙏"]

run = OrderPaymentWorkflow.resume(run, input: "paid Rp250.000 by bank transfer, receipt attached")
run.status          # => "running" — now polling the gateway on an ActiveJob timer
run.current_step    # => "watch_payment"
run.state["amount"] # => 250_000
```

This is `examples/order_payment.rb` (runnable: `bundle exec ruby examples/order_payment.rb`), covered end-to-end by `spec/omnibot/workflow_integration_spec.rb` — copy-paste it and swap in your own agent/gateway calls.

A step body runs at most once per entry: `wait_for_input` throws out of the step immediately (statements after it never run), so bodies need no idempotence gymnastics. After a step returns normally, transitions are evaluated in declaration order — first matching `if:` wins (unconditional always matches) — and the run walks into the next step in the same activation, stopping only at `wait_for_input`, `handover!`, a poll schedule, a terminal step (`:done`, `:expired`, `:failed`, `:cancelled`, or any user step with no outgoing transitions), or an exception (→ `failed`, with `run.error` set).

**Replies have two delivery paths.** Foreground activations (`start`/`resume`) return the activation's replies on `run.replies`. Background activations — a poll tick or a timeout firing via `Omnibot::WorkflowTimerJob` — have no caller to return to, so `reply` *always* also emits `omnibot.workflow.reply`; that's the one seam for both. Bridge it to your message provider with a one-line subscriber:

```ruby
ActiveSupport::Notifications.subscribe("omnibot.workflow.reply") do |event|
  YourMessenger.send(event.payload[:run_id], event.payload[:text])
end
```

**Human handover and control operations:**

```ruby
run.status              # => "waiting_for_human" after a step calls handover!(reason: "...")
run.resume_from_human    # re-enters the current step as a fresh attempt
run.retry!               # re-enters a *failed* run's current step (attempts increments)
run.cancel!               # any active run -> "cancelled"; raises Omnibot::WorkflowError::StaleResume if already terminal
```

`resume` raises `Omnibot::WorkflowError::StaleResume` when the run is terminal (`done`/`failed`/`expired`/`cancelled`) or `waiting_for_human` (its own message points you at `resume_from_human` instead). `while_running :ignore` (the default) makes `resume` on a still-`running` run a no-op that returns it unchanged — this is the only mode v0.2 implements; `while_running :interrupt` (abort the in-flight step and apply the new input immediately) is documented but raises `NotImplementedError` and ships in v0.3. Resuming a run sitting at a `wait_for_input` checkpoint evaluates its transitions and re-enters; if that lands on another `wait_for_input` checkpoint, it simply resumes again next time.

Timers (`timeout :step, after:, to:`, and poll's `every:`) are ActiveJob, scheduled with `set(wait:)`, and stale-checked against a per-entry `timer_token` before they act — a fired timer from a step the run has since left is a safe no-op. **Running the example:** the demo and integration spec use ActiveJob's `:test` adapter with `perform_enqueued_jobs`, not `:inline` — `InlineAdapter#enqueue_at` isn't implemented in any ActiveJob version we've checked, so `:inline` can't run a `poll`/`timeout` step at all. See "Production queue adapters" below for real deployments.

**Production queue adapters:** schedule jobs fire through `Omnibot::WorkflowTimerJob` via ActiveJob, so `wait:` timing depends on your adapter's `enqueue_at` support (Sidekiq, Sidekiq Cron, GoodJob, etc. all handle it — `:inline` and `:async` don't). Set `Omnibot::WorkflowTimerJob.enqueue_after_transaction_commit` so a timer scheduled inside a still-open transaction doesn't fire before the transaction commits — on Rails 7.2 that setting takes a symbol (`= :always`); on Rails 8.0+ it also accepts a boolean (`= true`). On Rails 7.1 the setting doesn't exist at all — rely on the token guard instead: a rolled-back activation may still enqueue a harmless no-op job, but the job re-checks `status`/`current_step`/`timer_token` under `with_lock` before doing anything, so the stale timer just finds nothing to do (the `timer_token` guard makes it self-healing).

## Instrumentation

Everything is instrumented via `ActiveSupport::Notifications`, so you can wire usage logging, cost caps, or a dashboard without touching the gem:

| Event | Payload keys |
|---|---|
| `omnibot.llm.call` | `agent:` (agent class), `model:` (String), `usage:` (`Omnibot::Usage` — `input_tokens`/`output_tokens`) |
| `omnibot.tool.call` | `tool:` (tool class), `name:` (String), `args:` (Hash), `error:` (String, present only on failure) |
| `omnibot.agent.run` | `agent:` (agent class), `fast_path:` (Boolean), `usage:` (`Omnibot::Usage`) |

`omnibot.llm.call`'s `usage:` is per-call (that one provider round trip's final response). `omnibot.agent.run`'s `usage:` is the run total, summed across every provider round trip in the run — a single `Agent.run` can be several `omnibot.llm.call`s deep when the tool-calling loop goes more than one turn.

Workflow (v0.2) emits its own events on the same seam:

| Event | Payload keys |
|---|---|
| `omnibot.workflow.step` | `workflow:` (Workflow class), `run_id:`, `step:` (Symbol), `attempts:` (Integer), `status:` (String, the run's status after the step body ran), `error:` (String, present only when the step raised) |
| `omnibot.workflow.transition` | `workflow:`, `run_id:`, `from:` (Symbol), `to:` (Symbol) |
| `omnibot.workflow.reply` | `workflow:`, `run_id:`, `step:` (String — `run.current_step`), `text:` (String) |
| `omnibot.workflow.handover` | `workflow:`, `run_id:`, `step:` (String), `reason:` (whatever was passed to `handover!`) |
| `omnibot.workflow.timeout` | `workflow:`, `run_id:`, `step:` (Symbol) |

Timing is available on the event object itself (`event.duration`) for any subscribed event — it is not a payload key.

A minimal usage-log subscriber — the whole recipe is 4 lines:

```ruby
usage_log = []
ActiveSupport::Notifications.subscribe("omnibot.llm.call") do |event|
  usage_log << { model: event.payload[:model], tokens: event.payload[:usage].input_tokens }
end
```

Nothing in the gem phones home, ever — instrumentation is a local seam you subscribe to yourself.

## Roadmap

- **v0.2 — Workflow. Shipped.** A durable, ActiveRecord-checkpointed graph engine for multi-step conversations: steps as nodes, transitions as edges, `wait_for_input` to checkpoint and pause for the next inbound message, `handover!` to page a human. State persists as jsonb on a gem-owned `omnibot_workflow_runs` table, so a workflow survives a deploy or a restart mid-conversation without a Redis checkpointer. See [Durable workflows](#durable-workflows) above.
- **Next — hosted observability.** A subscriber gem plus a hosted dashboard, built entirely on the instrumentation events above (Agent and Workflow both). Paid, optional, and no core changes required to adopt it.
- **Next — `while_running :interrupt`.** Full semantics for aborting an in-flight step when a new message arrives mid-activation, if demand shows up; `:ignore` is the only implemented mode today.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
