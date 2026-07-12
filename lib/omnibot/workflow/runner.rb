module Omnibot
  class Workflow
    INTERRUPT = :__omnibot_workflow_interrupt

    # Runs inside run.with_lock, always.
    class Runner
      MAX_STEPS_PER_ACTIVATION = 100

      def initialize(run)
        @run = run
        @workflow = run.workflow_class
      end

      # Enter `step` (fresh entry or re-entry), then follow transitions
      # until an interrupt, terminal step, or error stops the loop.
      def enter(step, input: nil)
        iterations = 0
        loop do
          iterations += 1
          if iterations > MAX_STEPS_PER_ACTIVATION
            return fail_run("activation exceeded #{MAX_STEPS_PER_ACTIVATION} step entries " \
                             "(transition loop at :#{step}?)")
          end
          record_entry(step)
          ctx = ExecutionContext.new(@run, @workflow, input)
          outcome = execute_body(step, ctx)
          case outcome
          in { interrupt: :wait_input } then return checkpoint("waiting_for_input")
          in { interrupt: :handover }   then return checkpoint("waiting_for_human")
          in { error: e }               then return fail_run(e.message)
          in { completed: true }
            input = nil # input is consumed by the first step that runs after resume
            nxt = next_step_from(step, ctx)
            return if nxt.nil? # fail_run already called
            return complete(nxt) if TERMINAL_STEPS.include?(nxt)
            step = nxt
          end
        end
      end

      # Placeholder — polling ships in Task 7.
      def poll_tick(step); end

      private

      def record_entry(step)
        # attempts.positive? distinguishes a genuine first entry (attempts=0, current_step
        # pre-seeded by create!) from a re-entry into the same step.
        same = @run.current_step == step.to_s && @run.attempts.positive?
        @run.attempts    = same ? @run.attempts + 1 : 1
        @run.current_step = step.to_s
        @run.timer_token += 1
        @run.step_entered_at = Time.current
        @run.save!

        if (t = @workflow.timeouts[step])
          WorkflowTimerJob.set(wait: t[:after])
                          .perform_later(@run.id, step.to_s, @run.timer_token, "timeout")
        end
      end

      def execute_body(step, ctx)
        body = @workflow.steps.fetch(step)[:body]
        ActiveSupport::Notifications.instrument(
          "omnibot.workflow.step",
          workflow: @workflow, run_id: @run.id, step: step, attempts: @run.attempts
        ) do |payload|
          interrupted = catch(INTERRUPT) do
            ctx.instance_exec(&body)
            nil
          end
          payload[:status] = @run.status
          interrupted ? { interrupt: interrupted } : { completed: true }
        rescue StandardError => e
          payload[:error] = e.message
          payload[:status] = "failed"
          { error: e }
        end
      end

      def next_step_from(step, ctx)
        rules = @workflow.transitions.select { |t| t[:from] == step }
        return :done if rules.empty? # terminal-by-absence
        rule = rules.find { |t| t[:if].nil? || ctx.instance_exec(&t[:if]) }
        if rule.nil?
          fail_run("no transition matched from :#{step}")
          return nil
        end
        ActiveSupport::Notifications.instrument(
          "omnibot.workflow.transition",
          workflow: @workflow, run_id: @run.id, from: step, to: rule[:to]
        )
        rule[:to]
      end

      def complete(terminal_step)
        if terminal_step == :done && (hook = @workflow.on_complete_hook)
          begin
            ExecutionContext.new(@run, @workflow, nil).instance_exec(&hook)
          rescue StandardError => e
            # ponytail: a completed workflow whose hook failed lands in failed — retry! re-runs the
            # FINAL step, so hooks should be idempotent
            return fail_run("on_complete hook raised: #{e.message}")
          end
        end
        @run.update!(status: terminal_step.to_s)
      end

      def fail_run(message)
        @run.update!(status: "failed", error: message)
      end

      def checkpoint(status)
        @run.update!(status: status)
      end
    end

    class ExecutionContext
      attr_reader :run, :input

      def initialize(run, workflow, input)
        @run = run
        @workflow = workflow
        @input = input
        define_state_proxy
      end

      def state = @state_proxy
      def attempts = @run.attempts

      def reply(text)
        @run.replies << text
        ActiveSupport::Notifications.instrument(
          "omnibot.workflow.reply",
          workflow: @workflow, run_id: @run.id, step: @run.current_step, text: text
        )
        text
      end

      def wait_for_input = throw(INTERRUPT, :wait_input)

      def handover!(reason: nil)
        ActiveSupport::Notifications.instrument(
          "omnibot.workflow.handover",
          workflow: @workflow, run_id: @run.id, step: @run.current_step, reason: reason
        )
        throw(INTERRUPT, :handover)
      end

      def poll_again = throw(INTERRUPT, :poll_again) # wired fully in Task 7

      private

      def define_state_proxy
        run = @run
        keys = @workflow.state_keys
        @state_proxy = Object.new
        keys.each do |key|
          @state_proxy.define_singleton_method(key) { run.state[key.to_s] }
          @state_proxy.define_singleton_method("#{key}=") do |v|
            run.state = run.state.merge(key.to_s => v)
          end
        end
      end
    end
  end
end
