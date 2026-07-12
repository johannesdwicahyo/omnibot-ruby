require_relative "lib/omnibot/version"

Gem::Specification.new do |spec|
  spec.name          = "omnibot-ruby"
  spec.version       = Omnibot::VERSION
  spec.authors       = ["Johannes Dwicahyo"]
  spec.email         = ["johannesdwicahyo@gmail.com"]
  spec.summary       = "Rails-first LLM agents for Ruby"
  spec.description   = "Agent framework for Rails: bounded tool-calling loops, fast paths, structured extraction, and (v0.2) durable workflows on ActiveRecord. Built on ruby_llm."
  spec.homepage      = "https://github.com/johannesdwicahyo/omnibot-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files         = Dir["lib/**/*.{rb,tt}", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]
  spec.metadata      = { "source_code_uri" => spec.homepage, "rubygems_mfa_required" => "true" }

  spec.add_dependency "ruby_llm", ">= 1.15"
  spec.add_dependency "activesupport", ">= 7.1"
  spec.add_dependency "activerecord", ">= 7.1"
  spec.add_dependency "activejob", ">= 7.1"
end
