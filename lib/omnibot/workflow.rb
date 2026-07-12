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
