RSpec.describe "Agent streaming" do
  include Omnibot::Testing::Helpers

  before { Omnibot::Testing.fake! }
  after  { Omnibot::Testing.reset! }

  let(:agent_class) do
    Class.new(Omnibot::Agent) do
      instructions "streamer"
      fast_path { |m, _| reply("fast!") if m == "fast" }
    end
  end

  it "yields string chunks to the stream lambda" do
    stub_agent(agent_class).then_reply("hello wide world")
    chunks = []
    result = agent_class.run("hi", stream: ->(c) { chunks << c })
    expect(chunks).to all(be_a(String))
    expect(chunks.join).to eq("hello wide world")
    expect(result.text).to eq("hello wide world")
  end

  it "does not stream fast-path replies" do
    chunks = []
    result = agent_class.run("fast", stream: ->(c) { chunks << c })
    expect(chunks).to be_empty
    expect(result.text).to eq("fast!")
  end

  it "guards nil and empty chunk content from real providers (I5)" do
    chunk_class = Struct.new(:content)
    received = []
    agent = agent_class.new
    wrapped = agent.send(:wrap_stream, ->(c) { received << c })

    wrapped.call(chunk_class.new(nil))
    wrapped.call(chunk_class.new(""))
    wrapped.call(chunk_class.new("hi"))

    expect(received).to eq(["hi"])
  end
end
