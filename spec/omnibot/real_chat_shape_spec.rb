# Exercises Agent#run_loop against a stub chat that mimics real ruby_llm 1.16
# object shapes (RubyLLM::Message / RubyLLM::ToolCall / RubyLLM::Message::Tokens),
# not FakeChat's plain hashes. FakeChat can't reproduce these bugs because its
# messages never carry #tool_calls/#tool_call_id/#tokens.
RSpec.describe "Agent against a real-shaped chat (C1 + I3)" do
  StubTokens = Struct.new(:input, :output)
  StubToolCall = Struct.new(:id, :name, :arguments, keyword_init: true)
  StubMessage = Struct.new(:role, :content, :tool_calls, :tool_call_id, :tokens, keyword_init: true)

  # Mimics ruby_llm::Chat closely enough for Agent#run_loop: a single top-level
  # #ask internally loops through the scripted tool-calling rounds (as real
  # ruby_llm's complete_once -> handle_tool_calls recursion does), appending the
  # assistant message (with tool_calls) to #messages BEFORE before_tool_call fires
  # for each call in that round -- the exact ordering C1 depends on.
  class StubChat
    attr_reader :messages

    def initialize(script)
      @messages = []
      @script = script.dup
      @hooks = []
    end

    def with_instructions(*) = self
    def with_tools(*tools, replace: false) = self
    def before_tool_call(&blk) = (@hooks << blk; self)

    def add_message(role:, content:, tool_call_id: nil)
      msg = StubMessage.new(role: role, content: content, tool_call_id: tool_call_id)
      @messages << msg
      msg
    end

    def ask(message, &_stream)
      @messages << StubMessage.new(role: :user, content: message)

      loop do
        step = @script.shift
        raise "StubChat: script exhausted" unless step

        case step[:kind]
        when :tool_calls
          assistant = StubMessage.new(role: :assistant, content: "", tool_calls: step[:tool_calls], tokens: step[:tokens])
          @messages << assistant
          step[:tool_calls].each_value do |tc|
            @hooks.each { |h| h.call(tc) } # may raise TurnLimit, same as real before_tool_call
            add_message(role: :tool, content: "tool-result:#{tc.id}", tool_call_id: tc.id)
          end
        when :final
          final = StubMessage.new(role: :assistant, content: step[:content], tokens: step[:tokens])
          @messages << final
          return final
        end
      end
    end
  end

  include Omnibot::Testing::Helpers

  around do |example|
    original_factory = Omnibot.chat_factory
    example.run
    Omnibot.chat_factory = original_factory
  end

  it "fills dangling tool calls with synthetic results and does not double-answer already-answered ones" do
    tc1 = StubToolCall.new(id: "call_1", name: "noop", arguments: {})
    tc2 = StubToolCall.new(id: "call_2", name: "noop", arguments: {})
    script = [
      { kind: :tool_calls, tool_calls: { "call_1" => tc1, "call_2" => tc2 }, tokens: StubTokens.new(5, 7) },
      { kind: :final, content: "final answer", tokens: StubTokens.new(3, 4) }
    ]
    stub_chat = StubChat.new(script)
    Omnibot.chat_factory = ->(model:, **) { stub_chat }

    agent_class = Class.new(Omnibot::Agent) do
      instructions "x"
      max_turns 1 # 2nd tool call in the parallel batch exceeds this
      tool(:noop, "noop") { |**| "ok" }
    end

    result = agent_class.run("go", context: {})

    tool_msgs = stub_chat.messages.select { |m| m.role == :tool }
    expect(tool_msgs.map(&:tool_call_id)).to contain_exactly("call_1", "call_2")
    expect(tool_msgs.find { |m| m.tool_call_id == "call_1" }.content).to eq("tool-result:call_1") # already answered, untouched
    expect(tool_msgs.find { |m| m.tool_call_id == "call_2" }.content).to eq("(turn limit reached)") # dangling, synthesized
    expect(result.text).to eq("final answer")
  end

  it "sums tokens across every message in the run, not just the final response" do
    tc = StubToolCall.new(id: "call_1", name: "noop", arguments: {})
    script = [
      { kind: :tool_calls, tool_calls: { "call_1" => tc }, tokens: StubTokens.new(5, 7) },
      { kind: :final, content: "final answer", tokens: StubTokens.new(3, 4) }
    ]
    stub_chat = StubChat.new(script)
    Omnibot.chat_factory = ->(model:, **) { stub_chat }

    agent_class = Class.new(Omnibot::Agent) do
      instructions "x"
      max_turns 5
      tool(:noop, "noop") { |**| "ok" }
    end

    result = agent_class.run("go", context: {})

    expect(result.usage.input_tokens).to eq(5 + 3)
    expect(result.usage.output_tokens).to eq(7 + 4)
  end
end
