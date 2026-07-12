require "active_record"

module Omnibot
  class WorkflowRun < ActiveRecord::Base
    self.table_name = "omnibot_workflow_runs"
    self.inheritance_column = nil # `type` stores the workflow class name, not STI

    ACTIVE_STATUSES   = %w[running waiting_for_input waiting_for_human].freeze
    TERMINAL_STATUSES = %w[done failed expired cancelled].freeze

    belongs_to :ref, polymorphic: true, optional: true

    attr_accessor :replies

    after_initialize { @replies ||= [] }

    def active?   = ACTIVE_STATUSES.include?(status)
    def terminal? = TERMINAL_STATUSES.include?(status)
    def workflow_class = type.constantize
  end
end
