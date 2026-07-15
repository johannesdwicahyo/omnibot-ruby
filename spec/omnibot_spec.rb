RSpec.describe Omnibot do
  it "has a version" do
    expect(Omnibot::VERSION).to eq("0.2.1")
  end

  it "configures default_model" do
    Omnibot.configure { |c| c.default_model = "claude-sonnet-5" }
    expect(Omnibot.config.default_model).to eq("claude-sonnet-5")
  ensure
    Omnibot.reset_config!
  end

  it "defaults on_tool_error to :capture" do
    expect(Omnibot.config.on_tool_error).to eq(:capture)
  end

  it "exposes a swappable chat_factory" do
    original = Omnibot.chat_factory
    Omnibot.chat_factory = ->(model:) { :fake }
    expect(Omnibot.chat_factory.call(model: "x")).to eq(:fake)
  ensure
    Omnibot.chat_factory = original
  end

  it "defines the error hierarchy" do
    expect(Omnibot::LLMError.ancestors).to include(Omnibot::Error)
    expect(Omnibot::ToolError.ancestors).to include(Omnibot::Error)
    expect(Omnibot::ExtractionError.ancestors).to include(Omnibot::Error)
  end
end
