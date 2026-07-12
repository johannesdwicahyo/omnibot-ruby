require "rails/generators"

module Omnibot
  module Generators
    class WorkflowGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      def create_workflow
        template "workflow.rb.tt", "app/workflows/#{file_name}_workflow.rb"
        template "workflow_spec.rb.tt", "spec/workflows/#{file_name}_workflow_spec.rb"
      end
    end
  end
end
