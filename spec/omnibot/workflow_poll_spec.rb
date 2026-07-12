RSpec.describe "Workflow poll steps" do
  include ActiveJob::TestHelper

  after { clear_enqueued_jobs }

  def gateway_flow(statuses)
    queue = statuses.dup
    stub_const("GATEWAY", -> { queue.shift })
    stub_const("PollFlow", Class.new(Omnibot::Workflow) do
      state :result
      step(:watch, poll: { every: 60, max_attempts: 3 }) do
        status = GATEWAY.call
        poll_again if status == :pending
        state.result = status
      end
      transition from: :watch, to: :done
    end)
  end

  it "runs tick 1 immediately and schedules the next on poll_again" do
    flow = gateway_flow(%i[pending paid])
    run = flow.start
    expect(run.status).to eq("running")
    expect(run.current_step).to eq("watch")
    expect(enqueued_jobs.last[:args][3]).to eq("poll")
  end

  it "completes when a tick does not poll_again" do
    flow = gateway_flow(%i[pending pending paid])
    run = flow.start
    perform_enqueued_jobs # tick 2 (pending → schedules tick 3)
    perform_enqueued_jobs # tick 3 (paid → falls through to done)
    expect(run.reload.status).to eq("done")
    expect(run.state["result"]).to eq("paid")
    expect(run.attempts).to eq(3)
  end

  it "expires after max_attempts ticks" do
    flow = gateway_flow(%i[pending pending pending pending])
    run = flow.start
    3.times { perform_enqueued_jobs }
    expect(run.reload.status).to eq("expired")
  end

  it "fails the run when poll_again is called from a non-poll step" do
    flow = stub_const("NoPoll", Class.new(Omnibot::Workflow) do
      step(:plain) { poll_again }
      transition from: :plain, to: :done
    end)
    run = nil
    expect { run = flow.start }.not_to raise_error
    expect(run.status).to eq("failed")
    expect(run.error).to match(/poll_again called from non-poll step/)
  end

  it "routes exhaustion to a declared timeout target instead" do
    queue = %i[pending pending pending pending]
    stub_const("GW2", -> { queue.shift })
    flow = stub_const("PollEsc", Class.new(Omnibot::Workflow) do
      step(:watch, poll: { every: 60, max_attempts: 2 }) do
        poll_again if GW2.call == :pending
      end
      step(:escalate) { handover! reason: "poll exhausted" }
      transition from: :watch, to: :done
      transition from: :escalate, to: :done
      timeout :watch, after: 3600, to: :escalate
    end)
    run = flow.start
    # Drive poll ticks directly (bypassing the generic timeout job) so the
    # assertion proves poll_tick's exhaustion routing, not the timeout path.
    # Tick 2 runs the body (pending, reschedules); tick 3 sees attempts 2 >= 2
    # and routes to :escalate.
    2.times { Omnibot::WorkflowTimerJob.perform_now(run.id, "watch", run.reload.timer_token, "poll") }
    expect(run.reload.status).to eq("waiting_for_human")
    expect(run.current_step).to eq("escalate")
  end
end
