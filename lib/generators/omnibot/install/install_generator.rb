require "rails/generators"

module Omnibot
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb.tt", "config/initializers/omnibot.rb"
      end
    end
  end
end
