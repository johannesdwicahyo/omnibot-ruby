RSpec.describe Omnibot::Testing do
  include Omnibot::Testing::Helpers

  let(:agent_class) { Class.new } # any class works as a registry key

  let(:echo_tool_class) do
    Omnibot::Tool.from_block(:echo, "Echoes") { |text:| "echo: #{text}" }
  end

  after { Omnibot::Testing.reset! }

  it "fake! swaps the chat factory and reset! restores it" do
    original = Omnibot.chat_factory
    Omnibot::Testing.fake!
    expect(Omnibot.chat_factory).not_to eq(original)
    Omnibot::Testing.reset!
    expect(Omnibot.chat_factory).to eq(original)
  end

  it "replays a scripted tool call + reply, executing the real tool" do
    Omnibot::Testing.fake!
    stub_agent(agent_class)
      .to_call_tool(:echo, text: "hi")
      .then_reply("done")

    chat = Omnibot.chat_factory.call(model: "x", agent_class: agent_class)
    chat.with_tools(echo_tool_class.new)
    seen = []
    chat.before_tool_call { |tc| seen << tc.name }

    response = chat.ask("go")
    expect(response.content).to eq("done")
    expect(seen).to eq(["echo"])
    expect(chat.tool_results).to eq(["echo: hi"])
  end

  it "streams the reply in chunks when a block is given" do
    Omnibot::Testing.fake!
    stub_agent(agent_class).then_reply("hello wide world")
    chat = Omnibot.chat_factory.call(model: "x", agent_class: agent_class)
    chunks = []
    chat.ask("go") { |c| chunks << c.content }
    expect(chunks.join).to eq("hello wide world")
    expect(chunks.length).to be > 1
  end

  it "answers unscripted asks with a default" do
    Omnibot::Testing.fake!
    chat = Omnibot.chat_factory.call(model: "x", agent_class: agent_class)
    expect(chat.ask("ping").content).to eq("(fake) ping")
  end
end
