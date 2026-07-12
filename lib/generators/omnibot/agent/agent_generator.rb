require "rails/generators"

module Omnibot
  module Generators
    class AgentGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      def create_agent
        template "agent.rb.tt", "app/agents/#{file_name}_agent.rb"
        template "agent_spec.rb.tt", "spec/agents/#{file_name}_agent_spec.rb"
      end
    end
  end
end
