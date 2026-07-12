module Omnibot
  class Agent
    class TurnLimit < StandardError; end

    FAST_REPLY = :__omnibot_fast_reply

    class << self
      def model(value = nil)
        value ? @model = value : (@model || Omnibot.config.default_model)
      end

      def instructions(value = nil)
        value ? @instructions = value : @instructions
      end

      def max_turns(value = nil)
        value ? @max_turns = value : (@max_turns || 5)
      end

      def tool(name_or_class, description = nil, &block)
        tools << (block ? Tool.from_block(name_or_class, description, &block) : name_or_class)
      end

      def tools = @tools ||= []
      def fast_paths = @fast_paths ||= []
      def fast_path(&block) = fast_paths << block

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@model, @model)
        subclass.instance_variable_set(:@instructions, @instructions)
        subclass.instance_variable_set(:@max_turns, @max_turns)
        subclass.instance_variable_set(:@tools, tools.dup)
        subclass.instance_variable_set(:@fast_paths, fast_paths.dup)
      end

      def run(message, history: [], context: {}, stream: nil)
        new(context).run(message, history: history, stream: stream)
      end
    end

    attr_reader :context

    def initialize(context = {})
      @context = context
    end

    def run(message, history: [], stream: nil)
      ActiveSupport::Notifications.instrument("omnibot.agent.run", agent: self.class) do |payload|
        payload[:fast_path] = false
        result = run_loop(message, history, stream)
        payload[:fast_path] = result.fast_path?
        payload[:usage] = result.usage
        result
      end
    end

    # Override in subclasses to gate tools per run (context-aware).
    def tools_for(_context) = self.class.tools

    # Called from within a fast_path block to short-circuit the run loop.
    def reply(text) = throw(FAST_REPLY, text)

    private

    def run_loop(message, history, stream)
      if (text = try_fast_paths(message))
        return Result.new(text: text, tool_calls: [], usage: Usage.new(0, 0),
                           messages: [], fast_path: true)
      end

      @history_for_build = history
      chat = build_chat
      tool_calls = []
      turns = 0

      chat.before_tool_call do |tc|
        turns += 1
        raise TurnLimit if turns > self.class.max_turns
        tool_calls << ToolCallRecord.new(tc.name.to_s, tc.arguments)
      end

      response =
        begin
          instrument_llm { chat.ask(message, &wrap_stream(stream)) }
        rescue TurnLimit
          strip_tools(chat)
          instrument_llm do
            chat.ask("Answer the user now with the information you already have. Do not call tools.",
                     &wrap_stream(stream))
          end
        end

      Result.new(
        text: response.content.to_s,
        tool_calls: tool_calls,
        usage: usage_from(response),
        messages: chat.messages.map { |m| normalize_message(m) },
        fast_path: false
      )
    end

    def try_fast_paths(message)
      self.class.fast_paths.each do |block|
        result = catch(FAST_REPLY) do
          instance_exec(message, context, &block)
          nil
        end
        return result if result
      end
      nil
    end

    def build_chat
      chat = Omnibot.chat_factory.call(model: self.class.model, agent_class: self.class)
      chat.with_instructions(interpolated_instructions) if self.class.instructions
      attach_history(chat)
      tools = tools_for(context).map { |t| t.is_a?(Class) ? t.new(context) : t }
      chat.with_tools(*tools) if tools.any?
      chat
    end

    def interpolated_instructions
      self.class.instructions.gsub(/\{\{(\w+)\}\}/) do
        context.fetch(Regexp.last_match(1).to_sym).to_s
      end
    end

    def attach_history(chat)
      # accepts hashes or role/content duck-typed objects (e.g. AR models)
      Array(@history_for_build).each do |m|
        role    = m.respond_to?(:role)    ? m.role    : m[:role]
        content = m.respond_to?(:content) ? m.content : m[:content]
        chat.add_message(role: role.to_sym, content: content)
      end
    end

    def wrap_stream(stream)
      return nil unless stream
      ->(chunk) { stream.call(chunk.content) }
    end

    def instrument_llm(&)
      ActiveSupport::Notifications.instrument(
        "omnibot.llm.call", agent: self.class, model: self.class.model
      ) do |payload|
        response = yield
        payload[:usage] = usage_from(response)
        response
      end
    end

    def usage_from(response)
      tokens = response.respond_to?(:tokens) ? response.tokens : nil
      Usage.new(tokens&.input || 0, tokens&.output || 0)
    end

    def strip_tools(chat)
      chat.with_tools(replace: true)
    end

    def normalize_message(m)
      if m.is_a?(Hash)
        { role: m[:role].to_sym, content: m[:content] }
      else
        { role: m.role.to_sym, content: m.content }
      end
    end
  end
end
