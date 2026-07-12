RSpec.describe "Agent fast paths and tool gating" do
  include Omnibot::Testing::Helpers

  before { Omnibot::Testing.fake! }
  after  { Omnibot::Testing.reset! }

  let(:agent_class) do
    Class.new(Omnibot::Agent) do
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
  end

  it "short-circuits on the first matching fast path with zero LLM usage" do
    result = agent_class.run("halo kak")
    expect(result.text).to eq("Halo! Ada yang bisa dibantu?")
    expect(result.fast_path?).to be(true)
    expect(result.usage.input_tokens).to eq(0)
  end

  it "checks fast paths in declaration order" do
    result = agent_class.run("hi", context: { vip: true })
    expect(result.text).to eq("Halo! Ada yang bisa dibantu?")
  end

  it "falls through to the LLM when no fast path replies" do
    stub_agent(agent_class).then_reply("normal flow")
    expect(agent_class.run("where is my order").text).to eq("normal flow")
  end

  it "gates tools via tools_for" do
    stub_agent(agent_class).to_call_tool(:lookup).then_reply("ok")
    result = agent_class.run("order status", context: { angry: true })
    expect(result.text).to eq("ok")
    # escalate must not be attachable: scripting it should raise
    stub_agent(agent_class).to_call_tool(:escalate).then_reply("nope")
    expect { agent_class.run("order status", context: { angry: true }) }
      .to raise_error(Omnibot::Error, /no tool "escalate"/)
  end

  it "emits omnibot.agent.run with fast_path: true" do
    events = []
    ActiveSupport::Notifications.subscribed(->(*a) { events << a.last }, "omnibot.agent.run") do
      agent_class.run("halo")
    end
    expect(events.first[:fast_path]).to be(true)
  end
end
