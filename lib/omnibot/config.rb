module Omnibot
  class Config
    attr_accessor :default_model, :on_tool_error

    def initialize
      @default_model = "gpt-4o-mini"
      @on_tool_error = :capture
    end
  end

  class << self
    def config = @config ||= Config.new
    def configure = yield(config)
    def reset_config! = @config = nil

    def chat_factory
      @chat_factory ||= ->(model:) { RubyLLM.chat(model: model) }
    end
    attr_writer :chat_factory
  end
end
