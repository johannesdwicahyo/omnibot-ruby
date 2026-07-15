RSpec.describe "Per-agent chat_factory" do
  include Omnibot::Testing::Helpers

  after { Omnibot::Testing.reset! }

  def scripted_fake_chat_factory(seen)
    lambda do |model:, agent_class: nil, **|
      seen << model
      Omnibot::Testing::FakeChat.new(agent_class: agent_class)
    end
  end

  it "uses the class-level factory for run instead of the global" do
    seen = []
    klass = Class.new(Omnibot::Agent) do
      model "gpt-4o-mini"
      instructions "hi"
    end
    klass.chat_factory(scripted_fake_chat_factory(seen))
    Omnibot::Testing.script_for(klass) << [:reply, "from class factory"]

    result = klass.run("hello")
    expect(result.text).to eq("from class factory")
    expect(seen).to eq(["gpt-4o-mini"])
  end

  it "uses the class-level factory for extract" do
    seen = []
    klass = Class.new(Omnibot::Agent) { instructions "x" }
    klass.chat_factory(scripted_fake_chat_factory(seen))
    Omnibot::Testing.script_for(klass) << [:reply, { "ok" => true }]

    expect(klass.extract("input", schema: Class.new)).to eq({ ok: true })
    expect(seen.length).to eq(1)
  end

  it "is inherited by subclasses and overridable" do
    parent_seen = []
    parent = Class.new(Omnibot::Agent) { instructions "p" }
    parent.chat_factory(scripted_fake_chat_factory(parent_seen))
    child = Class.new(parent)
    Omnibot::Testing.script_for(child) << [:reply, "child ran"]

    expect(child.run("go").text).to eq("child ran")
    expect(parent_seen.length).to eq(1)
  end

  it "falls back to the global factory when no class factory is declared" do
    Omnibot::Testing.fake!
    klass = Class.new(Omnibot::Agent) { instructions "x" }
    stub_agent(klass).then_reply("global path")
    expect(klass.run("hi").text).to eq("global path")
  end

  it "Testing.fake! overrides a class-level factory so specs stay offline" do
    hits = []
    klass = Class.new(Omnibot::Agent) { instructions "x" }
    klass.chat_factory(->(**) { hits << :real; raise "must not be called under fake!" })

    Omnibot::Testing.fake!
    stub_agent(klass).then_reply("faked")
    expect(klass.run("hi").text).to eq("faked")
    expect(hits).to be_empty
  end
end
