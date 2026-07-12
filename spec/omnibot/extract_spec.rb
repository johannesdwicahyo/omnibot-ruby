RSpec.describe "Agent.extract" do
  include Omnibot::Testing::Helpers

  before { Omnibot::Testing.fake! }
  after  { Omnibot::Testing.reset! }

  let(:agent_class) { Class.new(Omnibot::Agent) { instructions "extractor" } }
  let(:schema) { Class.new } # schema object is passed through; FakeChat ignores it

  it "returns the parsed hash when the provider auto-parses" do
    stub_agent(agent_class).then_extract({ "amount" => 50_000, "bank" => "BCA" })
    result = agent_class.extract("transfer 50rb via BCA", schema: schema)
    expect(result).to eq({ amount: 50_000, bank: "BCA" })
  end

  it "parses a JSON string reply" do
    stub_agent(agent_class).then_reply('{"amount": 50000}')
    expect(agent_class.extract("x", schema: schema)).to eq({ amount: 50_000 })
  end

  it "repairs once on invalid JSON, then succeeds" do
    stub_agent(agent_class).then_reply("not json").then_reply('{"ok": true}')
    expect(agent_class.extract("x", schema: schema)).to eq({ ok: true })
  end

  it "raises ExtractionError after a failed repair" do
    stub_agent(agent_class).then_reply("nope").then_reply("still nope")
    expect { agent_class.extract("x", schema: schema) }
      .to raise_error(Omnibot::ExtractionError, /still nope/i)
  end

  it "includes the JSON parse error message in the repair ask (T5)" do
    stub_agent(agent_class).then_reply("not json").then_reply('{"ok": true}')

    original_factory = Omnibot.chat_factory
    captured_chat = nil
    Omnibot.chat_factory = lambda { |model:, **kw|
      captured_chat = original_factory.call(model: model, **kw)
    }

    agent_class.extract("x", schema: schema)

    repair_message = captured_chat.messages.find { |m| m[:role] == :user && m[:content].to_s.include?("not valid JSON") }
    expect(repair_message).not_to be_nil
    expect(repair_message[:content]).to include("unexpected token")
  ensure
    Omnibot.chat_factory = original_factory
  end
end
