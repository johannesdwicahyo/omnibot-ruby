require "omnibot"
require_relative "support/active_record"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end
