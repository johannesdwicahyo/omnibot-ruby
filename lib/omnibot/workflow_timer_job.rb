module Omnibot
  class WorkflowTimerJob < ActiveJob::Base
    def perform(run_id, step, token, kind)
      run = WorkflowRun.find_by(id: run_id) or return
      run.replies = []
      run.with_lock do
        return unless run.active?
        return unless run.current_step == step && run.timer_token == token

        workflow = run.workflow_class
        case kind
        when "timeout"
          ActiveSupport::Notifications.instrument(
            "omnibot.workflow.timeout",
            workflow: workflow, run_id: run.id, step: step.to_sym
          )
          target = workflow.timeouts.fetch(step.to_sym)[:to]
          runner = Workflow::Runner.new(run)
          if Workflow::TERMINAL_STEPS.include?(target)
            runner.send(:complete, target)
          else
            run.update!(status: "running")
            runner.enter(target)
          end
        when "poll"
          Workflow::Runner.new(run).poll_tick(step.to_sym) # implemented in Task 7
        end
      end
    end
  end
end
