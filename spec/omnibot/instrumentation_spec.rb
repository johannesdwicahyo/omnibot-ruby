RSpec.describe "Instrumentation" do
  include Omnibot::Testing::Helpers

  before { Omnibot::Testing.fake! }
  after  { Omnibot::Testing.reset! }

  let(:agent_class) do
    Class.new(Omnibot::Agent) do
      instructions "support"
      tool(:lookup, "Lookup") { |**| "found" }
    end
  end

  it "supports a minimal usage-log subscriber (the README recipe)" do
    usage_log = []
    subscriber = ActiveSupport::Notifications.subscribe("omnibot.llm.call") do |event|
      usage_log << { model: event.payload[:model], tokens: event.payload[:usage].input_tokens }
    end

    stub_agent(agent_class).to_call_tool(:lookup).then_reply("done")
    agent_class.run("find it")

    expect(usage_log.length).to eq(1)
    expect(usage_log.first[:tokens]).to eq(10)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "emits llm.call, tool.call, and agent.run for one run" do
    names = []
    subscriber = ActiveSupport::Notifications.subscribe(/\Aomnibot\./) do |name, *|
      names << name
    end
    stub_agent(agent_class).to_call_tool(:lookup).then_reply("done")
    agent_class.run("find it")
    expect(names).to include("omnibot.llm.call", "omnibot.tool.call", "omnibot.agent.run")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
