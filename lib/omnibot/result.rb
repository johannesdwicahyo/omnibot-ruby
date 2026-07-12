module Omnibot
  Usage          = Struct.new(:input_tokens, :output_tokens)
  ToolCallRecord = Struct.new(:name, :arguments)

  Result = Struct.new(:text, :tool_calls, :usage, :messages, :fast_path, keyword_init: true) do
    def fast_path? = !!fast_path
  end
end
