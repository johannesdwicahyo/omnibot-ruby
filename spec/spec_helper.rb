require "omnibot"
require_relative "support/active_record"

require "active_job"
require "active_support/testing/time_helpers"
ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(IO::NULL)

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end
