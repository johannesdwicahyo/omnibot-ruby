module Omnibot
  module Testing
    FakeTokens   = Struct.new(:input, :output)
    FakeMessage  = Struct.new(:content, :tokens)
    FakeToolCall = Struct.new(:name, :arguments)

    class << self
      def fake!
        @original_factory ||= Omnibot.chat_factory
        fake = ->(model:, agent_class: nil, **) {
          FakeChat.new(agent_class: agent_class)
        }
        Omnibot.chat_factory = fake
        # Override beats per-agent chat_factory declarations, so specs stay
        # offline even for agents that configure their own factory.
        Omnibot.chat_factory_override = fake
      end

      def reset!
        Omnibot.chat_factory = @original_factory if @original_factory
        @original_factory = nil
        Omnibot.chat_factory_override = nil
        scripts.clear
      end

      def scripts = @scripts ||= {}
      def script_for(agent_class) = scripts[agent_class] ||= []
    end

    class StubBuilder
      def initialize(agent_class) = @script = Testing.script_for(agent_class)

      def to_call_tool(name, **args)
        @script << [:tool, name.to_s, args]
        self
      end

      def then_reply(text)
        @script << [:reply, text]
        self
      end

      def then_extract(hash)
        @script << [:reply, hash]
        self
      end
    end

    module Helpers
      def stub_agent(agent_class) = StubBuilder.new(agent_class)
    end

    class FakeChat
      attr_reader :messages, :tool_results

      def initialize(agent_class: nil)
        @agent_class = agent_class
        @messages = []
        @tools = []
        @before_tool_call_hooks = []
        @tool_results = []
      end

      def with_instructions(text, **)
        @messages << { role: :system, content: text }
        self
      end

      def with_tools(*tools, replace: false)
        @tools = [] if replace
        @tools.concat(tools)
        self
      end

      def add_message(role:, content:)
        @messages << { role: role, content: content }
        self
      end

      def before_tool_call(&blk)
        @before_tool_call_hooks << blk
        self
      end

      def with_schema(schema)
        @schema = schema
        self
      end

      def ask(message, &stream_block)
        @messages << { role: :user, content: message }
        script = Testing.script_for(@agent_class)

        while (step = script.shift)
          kind, a, b = step
          case kind
          when :tool
            tool_call = FakeToolCall.new(a, b)
            @before_tool_call_hooks.each { |h| h.call(tool_call) }
            tool = @tools.find { |t| t.name.to_s == a }
            raise Omnibot::Error, "FakeChat: no tool #{a.inspect} attached" unless tool
            @tool_results << tool.execute(**b)
          when :reply
            return emit_reply(a, stream_block)
          end
        end

        emit_reply("(fake) #{message}", stream_block)
      end

      private

      def emit_reply(text, stream_block)
        if stream_block && text.is_a?(String)
          text.split(/(?<= )/).each { |chunk| stream_block.call(FakeMessage.new(chunk, nil)) }
        end
        msg = FakeMessage.new(text, FakeTokens.new(10, 10))
        @messages << { role: :assistant, content: text }
        msg
      end
    end
  end
end
