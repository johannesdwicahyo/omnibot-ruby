module Omnibot
  class Tool < RubyLLM::Tool
    attr_reader :context

    def initialize(context = {})
      super()
      @context = context
    end

    # Wrap every subclass's #execute with error capture + instrumentation.
    def self.inherited(subclass)
      super
      subclass.prepend(SafeExecute) unless subclass.ancestors.include?(SafeExecute)
    end

    def self.from_block(name_sym, description_str, &block)
      Class.new(self) do
        description(description_str)
        # define execute from the block so ruby_llm signature inference
        # (v1.15+) derives the JSON schema from its keyword args
        define_method(:execute, &block)
        define_method(:name) { name_sym.to_s }
      end
    end

    module SafeExecute
      def execute(**kwargs)
        ActiveSupport::Notifications.instrument(
          "omnibot.tool.call", tool: self.class, args: kwargs
        ) do |payload|
          super
        rescue StandardError => e
          payload[:error] = e.message
          raise Omnibot::ToolError, e.message if Omnibot.config.on_tool_error == :raise
          { error: e.message }
        end
      end
    end
  end
end
