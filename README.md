# omnibot-ruby

Rails-first LLM agents for Ruby.

## Why

`omnibot-ruby` is a Rails-idiomatic agent framework built on [`ruby_llm`](https://github.com/crmne/ruby_llm) — a class DSL for bounded tool-calling agents that lives in your Rails app, not a Python sidecar you have to deploy, proxy, and keep in sync. It ships two primitives: **Agent** (v0.1, available now — a bounded tool-calling loop with fast paths, structured extraction, and streaming) and **Workflow** (coming in v0.2 — a durable, ActiveRecord-checkpointed graph engine for multi-step conversations with human handover, so long-running flows survive restarts without a Redis checkpointer). Everything runs in-process, which means token streaming to ActionCable/Turbo is a callback away instead of blocked behind an HTTP hop.

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

- The loop is: send → execute tool calls → append results → repeat, up to `max_turns`. On the final turn, tools are unbound so the model is forced to answer instead of looping forever.
- `instructions` support `{{var}}` interpolation from `context`; a missing variable raises `KeyError`.
- `history` is a plain array of `{ role:, content: }` hashes (or anything that responds to `#role`/`#content`) — the gem never persists conversations itself.
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
class DepositProof < RubyLLM::Schema
  string :bank
  integer :amount
end

class ProofAgent < Omnibot::Agent
  instructions "Extract the bank name and amount from the customer's message."
end

result = ProofAgent.extract("transfer 50rb via BCA", schema: DepositProof)
result # => { amount: 50_000, bank: "BCA" }
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

## Instrumentation

Everything is instrumented via `ActiveSupport::Notifications`, so you can wire usage logging, cost caps, or a dashboard without touching the gem:

| Event | Payload keys |
|---|---|
| `omnibot.llm.call` | `agent:` (agent class), `model:` (String), `usage:` (`Omnibot::Usage` — `input_tokens`/`output_tokens`) |
| `omnibot.tool.call` | `tool:` (tool class), `args:` (Hash), `error:` (String, present only on failure) |
| `omnibot.agent.run` | `agent:` (agent class), `fast_path:` (Boolean), `usage:` (`Omnibot::Usage`) |

Timing is available on the event object itself (`event.duration`) for any subscribed event — it is not a payload key. Workflow events (`omnibot.workflow.*`) arrive with Workflow in v0.2.

A minimal usage-log subscriber — the whole recipe is 4 lines:

```ruby
usage_log = []
ActiveSupport::Notifications.subscribe("omnibot.llm.call") do |event|
  usage_log << { model: event.payload[:model], tokens: event.payload[:usage].input_tokens }
end
```

Nothing in the gem phones home, ever — instrumentation is a local seam you subscribe to yourself.

## Roadmap

- **v0.2 — Workflow.** A durable, ActiveRecord-checkpointed graph engine for multi-step conversations: steps as nodes, transitions as edges, `wait_for_input` to checkpoint and pause for the next inbound message, `handover!` to page a human. State persists as jsonb on a gem-owned `omnibot_workflow_runs` table, so a workflow survives a deploy or a restart mid-conversation without a Redis checkpointer.
- **Later — hosted observability.** A subscriber gem plus a hosted dashboard, built entirely on the instrumentation events above. Paid, optional, and no core changes required to adopt it.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
