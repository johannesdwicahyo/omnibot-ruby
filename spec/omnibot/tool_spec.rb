RSpec.describe Omnibot::Tool do
  let(:tool_class) do
    Class.new(Omnibot::Tool) do
      description "Adds two numbers"
      param :a, desc: "First"
      param :b, desc: "Second"
      def execute(a:, b:) = a + b
    end
  end

  it "executes and returns the result" do
    expect(tool_class.new.execute(a: 1, b: 2)).to eq(3)
  end

  it "exposes context passed at construction" do
    expect(tool_class.new(company: "Wokku").context[:company]).to eq("Wokku")
  end

  it "captures errors as { error: } by default" do
    boom = Class.new(Omnibot::Tool) do
      description "Boom"
      def execute = raise "kaput"
    end
    expect(boom.new.execute).to eq({ error: "kaput" })
  end

  it "raises Omnibot::ToolError when on_tool_error is :raise" do
    Omnibot.configure { |c| c.on_tool_error = :raise }
    boom = Class.new(Omnibot::Tool) do
      description "Boom"
      def execute = raise "kaput"
    end
    expect { boom.new.execute }.to raise_error(Omnibot::ToolError, /kaput/)
  ensure
    Omnibot.reset_config!
  end

  it "emits omnibot.tool.call" do
    events = []
    ActiveSupport::Notifications.subscribed(->(*args) { events << args.last }, "omnibot.tool.call") do
      tool_class.new.execute(a: 1, b: 2)
    end
    expect(events.first[:tool]).to eq(tool_class)
    expect(events.first[:args]).to eq({ a: 1, b: 2 })
  end

  describe ".from_block" do
    it "builds a named tool whose execute runs the block" do
      klass = described_class.from_block(:shout, "Upcases") { |text:| text.upcase }
      tool = klass.new
      expect(tool.name).to eq("shout")
      expect(tool.execute(text: "hi")).to eq("HI")
    end

    it "gives the block access to context" do
      klass = described_class.from_block(:who, "Company") { |**| context[:company] }
      expect(klass.new(company: "Wokku").execute).to eq("Wokku")
    end
  end
end
