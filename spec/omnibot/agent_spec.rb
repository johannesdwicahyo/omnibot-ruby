RSpec.describe Omnibot::Agent do
  include Omnibot::Testing::Helpers

  before { Omnibot::Testing.fake! }
  after  { Omnibot::Testing.reset! }

  let(:agent_class) do
    Class.new(described_class) do
      model "claude-sonnet-5"
      instructions "You help customers of {{company}}."
      max_turns 3

      tool :lookup_order, "Find an order" do |order_id:|
        "order #{order_id}: shipped"
      end
    end
  end

  it "runs a scripted turn: tool call then reply" do
    stub_agent(agent_class)
      .to_call_tool(:lookup_order, order_id: 123)
      .then_reply("Order 123 is shipped!")

    result = agent_class.run("where is order 123?", context: { company: "Wokku" })

    expect(result.text).to eq("Order 123 is shipped!")
    expect(result.tool_calls.map(&:name)).to eq(["lookup_order"])
    expect(result.usage.input_tokens).to eq(10)
    expect(result.fast_path?).to be(false)
  end

  it "interpolates {{company}} into instructions" do
    stub_agent(agent_class).then_reply("ok")
    result = agent_class.run("hi", context: { company: "Wokku" })
    system_msg = result.messages.find { |m| m[:role] == :system }
    expect(system_msg[:content]).to include("customers of Wokku")
  end

  it "raises KeyError when an interpolation variable is missing" do
    stub_agent(agent_class).then_reply("ok")
    expect { agent_class.run("hi", context: {}) }.to raise_error(KeyError)
  end

  it "injects history before the user message" do
    stub_agent(agent_class).then_reply("ok")
    result = agent_class.run("again?",
      history: [{ role: :user, content: "hello" }, { role: :assistant, content: "hi there" }],
      context: { company: "Wokku" })
    roles = result.messages.map { |m| m[:role] }
    expect(roles).to eq([:system, :user, :assistant, :user, :assistant])
  end

  it "subclasses inherit and can extend DSL state" do
    child = Class.new(agent_class) { max_turns 9 }
    expect(child.max_turns).to eq(9)
    expect(agent_class.max_turns).to eq(3)
    expect(child.tools.length).to eq(1)
  end

  it "uses config.default_model when model is not declared" do
    klass = Class.new(described_class) { instructions "x" }
    expect(klass.model).to eq(Omnibot.config.default_model)
  end

  it "stops tool loops at max_turns and forces a final answer" do
    looper = Class.new(described_class) do
      instructions "loop"
      max_turns 2
      tool(:noop, "No-op") { |**| "ok" }
    end
    stub_agent(looper)
      .to_call_tool(:noop).to_call_tool(:noop).to_call_tool(:noop)
    # No reply is scripted: the agent's before_tool_call hook raises TurnLimit on
    # the 3rd call (max_turns 2); the agent strips tools and asks once more — the
    # script is then empty, so the default "(fake) ..." reply proves the
    # forced-final-answer path ran.
    result = looper.run("go", context: {})
    expect(result.text).to start_with("(fake)")
    expect(result.tool_calls.length).to eq(2)
  end

  it "emits omnibot.agent.run" do
    stub_agent(agent_class).then_reply("ok")
    events = []
    ActiveSupport::Notifications.subscribed(->(*a) { events << a.last }, "omnibot.agent.run") do
      agent_class.run("hi", context: { company: "Wokku" })
    end
    expect(events.first[:agent]).to eq(agent_class)
    expect(events.first[:fast_path]).to be(false)
  end
end
