module Omnibot
  class Workflow
    TERMINAL_STEPS = %i[done expired failed cancelled].freeze
    WHILE_RUNNING_MODES = %i[ignore interrupt].freeze

    class << self
      def state(*keys) = keys.any? ? state_keys.concat(keys) : state_keys
      def state_keys = @state_keys ||= []

      def step(name, poll: nil, &body)
        steps[name.to_sym] = { body: body, poll: poll }
      end

      def steps = @steps ||= {}

      def transition(from:, to:, if: nil)
        cond = binding.local_variable_get(:if)
        transitions << { from: from.to_sym, to: to.to_sym, if: cond }
      end

      def transitions = @transitions ||= []

      def timeout(step, after:, to:)
        timeouts[step.to_sym] = { after: after, to: to.to_sym }
      end

      def timeouts = @timeouts ||= {}

      def on_complete(&blk) = blk ? @on_complete_hook = blk : nil
      def on_complete_hook = @on_complete_hook

      def while_running(mode = nil)
        return @while_running || :ignore if mode.nil?
        unless WHILE_RUNNING_MODES.include?(mode)
          raise ArgumentError, "while_running must be :ignore or :interrupt"
        end
        @while_running = mode
      end

      def start(ref: nil, state: {})
        first = steps.keys.first or raise WorkflowError, "#{name} declares no steps"
        run = WorkflowRun.create!(
          type: name, status: "running", current_step: first.to_s,
          state: state.transform_keys(&:to_s), attempts: 0, timer_token: 0,
          step_entered_at: Time.current, ref: ref
        )
        run.replies = []
        run.with_lock { Runner.new(run).enter(first) }
        run
      end

      def resume(run, input: nil)
        run.reload
        run.replies = []
        run.with_lock do
          case run.status
          when "waiting_for_input"
            step = run.current_step.to_sym
            ctx = ExecutionContext.new(run, self, input)
            runner = Runner.new(run)
            nxt = runner.send(:next_step_from, step, ctx)
            break if nxt.nil?
            if TERMINAL_STEPS.include?(nxt)
              runner.send(:complete, nxt)
            else
              runner.enter(nxt, input: input)
            end
          when "running"
            if while_running == :interrupt
              raise NotImplementedError, "while_running :interrupt ships in v0.3"
            end
            # :ignore — return unchanged
          when "waiting_for_human"
            raise WorkflowError::StaleResume, "use resume_from_human for waiting_for_human runs"
          else
            raise WorkflowError::StaleResume, "cannot resume a #{run.status} run"
          end
        end
        run
      end

      def resume_from_human(run, input: nil)
        control(run, allowed: %w[waiting_for_human]) do
          run.update!(status: "running")
          Runner.new(run).enter(run.current_step.to_sym, input: input)
        end
      end

      def retry!(run)
        control(run, allowed: %w[failed]) do
          run.update!(status: "running", error: nil)
          Runner.new(run).enter(run.current_step.to_sym)
        end
      end

      def cancel!(run)
        control(run, allowed: WorkflowRun::ACTIVE_STATUSES) do
          run.update!(status: "cancelled")
        end
      end

      private

      def control(run, allowed:)
        run.reload
        run.replies = []
        run.with_lock do
          unless allowed.include?(run.status)
            raise WorkflowError::StaleResume, "cannot perform this on a #{run.status} run"
          end
          yield
        end
        run
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@state_keys, state_keys.dup)
        subclass.instance_variable_set(:@steps, steps.dup)
        subclass.instance_variable_set(:@transitions, transitions.map(&:dup))
        subclass.instance_variable_set(:@timeouts, timeouts.dup)
        subclass.instance_variable_set(:@on_complete_hook, @on_complete_hook)
        subclass.instance_variable_set(:@while_running, @while_running)
      end
    end
  end
end
