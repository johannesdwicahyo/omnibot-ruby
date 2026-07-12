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

      # Bounds the number of tool executions in a run, not conversation rounds —
      # the before_tool_call hook counts each call, so parallel tool calls in a
      # single round each count separately.
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

      def extract(input, schema:, context: {})
        new(context).extract(input, schema: schema)
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

    def extract(input, schema:)
      chat = Omnibot.chat_factory.call(model: self.class.model, agent_class: self.class)
      chat.with_instructions(interpolated_instructions) if self.class.instructions
      chat.with_schema(schema)

      response = instrument_llm { chat.ask(input.to_s) }
      parse_extraction(response.content) do |error|
        repair = instrument_llm do
          chat.ask("Your previous output was not valid JSON (#{error.message}). " \
                    "Respond again with ONLY valid JSON matching the schema.")
        end
        parse_extraction(repair.content) do |_error|
          raise ExtractionError, "extraction failed after repair: #{repair.content.to_s.truncate(200)}"
        end
      end
    end

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
          synthesize_pending_tool_results(chat)
          instrument_llm do
            chat.ask("Answer the user now with the information you already have. Do not call tools.",
                     &wrap_stream(stream))
          end
        end

      Result.new(
        text: response.content.to_s,
        tool_calls: tool_calls,
        usage: run_usage(chat, response),
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
      ->(chunk) { stream.call(chunk.content) if chunk.content && !chunk.content.empty? }
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

    # Per-call usage (used for the omnibot.llm.call event): just the final response.
    def usage_from(response)
      tokens = response.respond_to?(:tokens) ? response.tokens : nil
      Usage.new(tokens&.input || 0, tokens&.output || 0)
    end

    # Run-level usage (Result#usage / omnibot.agent.run): one real `ask` can be N
    # provider round trips (tool-calling loop), so sum tokens across every message
    # that carries them. FakeChat's plain-hash messages never respond to #tokens,
    # so that falls back to the final response's usage — keeps fake-based specs green.
    def run_usage(chat, response)
      token_messages = chat.messages.select { |m| m.respond_to?(:tokens) && m.tokens }
      return usage_from(response) if token_messages.empty?

      Usage.new(
        token_messages.sum { |m| m.tokens.input || 0 },
        token_messages.sum { |m| m.tokens.output || 0 }
      )
    end

    def strip_tools(chat)
      chat.with_tools(replace: true)
    end

    # C1: against real ruby_llm, complete_once appends the assistant message
    # (with tool_calls) BEFORE before_tool_call fires, so raising TurnLimit out of
    # that hook leaves unanswered tool_call(s) in chat history. The follow-up
    # "answer now" user-role ask then 400s on OpenAI/Anthropic because every
    # tool_call must have a matching tool-result message. With parallel tool
    # calls, some of the batch may already have results while the rest dangle.
    # Duck-typed defensively: FakeChat's messages are plain hashes that don't
    # respond to #tool_calls, so this is a safe no-op there.
    def synthesize_pending_tool_results(chat)
      last_call_message = chat.messages.reverse_each.find do |m|
        m.respond_to?(:tool_calls) && m.tool_calls && !m.tool_calls.empty?
      end
      return unless last_call_message

      answered_ids = chat.messages.filter_map { |m| m.tool_call_id if m.respond_to?(:tool_call_id) && m.tool_call_id }

      last_call_message.tool_calls.each_value do |tc|
        next if answered_ids.include?(tc.id)
        chat.add_message(role: :tool, content: "(turn limit reached)", tool_call_id: tc.id)
      end
    end

    def parse_extraction(content)
      case content
      when Hash then content.deep_symbolize_keys
      when String
        begin
          JSON.parse(content, symbolize_names: true)
        rescue JSON::ParserError => e
          yield e
        end
      else
        yield JSON::ParserError.new("expected a JSON string or Hash, got #{content.class}")
      end
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
