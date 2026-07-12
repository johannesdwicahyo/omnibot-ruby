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
        define_method(:execute, &block)
        define_method(:name) { name_sym.to_s }
        # Declare params from the block's own signature: SafeExecute shadows
        # #execute with (**kwargs), so ruby_llm's signature inference sees no
        # keywords and would emit an empty schema.
        block.parameters.each do |kind, pname|
          param(pname) if kind == :keyreq
          param(pname, required: false) if kind == :key
        end
      end
    end

    # NOTE: this wrapper shadows execute's signature (method(:execute).parameters
    # becomes [[:keyrest, :kwargs]]), so ruby_llm signature inference cannot be
    # relied on — class-form tools must declare `param` explicitly.
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
