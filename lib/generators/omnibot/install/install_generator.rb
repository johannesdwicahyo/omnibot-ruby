require "rails/generators"
require "rails/generators/migration"

module Omnibot
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(_dir)
        Time.now.utc.strftime("%Y%m%d%H%M%S")
      end

      def create_initializer
        template "initializer.rb.tt", "config/initializers/omnibot.rb"
      end

      def create_workflow_runs_migration
        return if Dir[File.join(destination_root, "db/migrate/*_create_omnibot_workflow_runs.rb")].any?
        migration_template "create_omnibot_workflow_runs.rb.tt",
                            "db/migrate/create_omnibot_workflow_runs.rb"
      end
    end
  end
end
