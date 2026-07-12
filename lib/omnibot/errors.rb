module Omnibot
  class Error < StandardError; end
  class LLMError < Error; end
  class ToolError < Error; end
  class ExtractionError < Error; end
  class WorkflowError < Error
    class InvalidTransition < WorkflowError; end
    class StaleResume < WorkflowError; end
  end
end
