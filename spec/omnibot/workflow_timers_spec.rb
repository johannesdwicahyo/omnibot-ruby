RSpec.describe Omnibot::WorkflowTimerJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  after { clear_enqueued_jobs; travel_back }

  let(:flow) do
    stub_const("TimedFlow", Class.new(Omnibot::Workflow) do
      step(:ask) { wait_for_input }
      step(:late) { }
      transition from: :ask, to: :done
      transition from: :late, to: :done
      timeout :ask, after: 30 * 60, to: :expired
    end)
  end

  it "schedules a timeout job on entering a step with a timeout" do
    flow.start
    expect(enqueued_jobs.size).to eq(1)
    job = enqueued_jobs.first
    expect(job[:job]).to eq(described_class)
    expect(job[:args][1]).to eq("ask")
    expect(job[:args][3]).to eq("timeout")
  end

  it "expires the run when the timer fires on the same step+token" do
    run = flow.start
    perform_enqueued_jobs
    expect(run.reload.status).to eq("expired")
  end

  it "no-ops when the run moved on before the timer fired (stale token)" do
    run = flow.start
    flow.resume(run, input: "answered in time")
    expect(run.reload.status).to eq("done")
    perform_enqueued_jobs
    expect(run.reload.status).to eq("done") # stale timer did nothing
  end

  it "no-ops when the run row was deleted" do
    run = flow.start
    run.delete
    expect { perform_enqueued_jobs }.not_to raise_error
  end

  it "routes timeout to a non-terminal step when declared" do
    f = stub_const("Reroute", Class.new(Omnibot::Workflow) do
      step(:ask)  { wait_for_input }
      step(:nag)  { reply "still there?" }
      transition from: :ask, to: :done
      transition from: :nag, to: :done
      timeout :ask, after: 60, to: :nag
    end)
    events = []
    sub = ActiveSupport::Notifications.subscribe("omnibot.workflow.reply") { |e| events << e.payload[:text] }
    run = f.start
    perform_enqueued_jobs
    expect(run.reload.status).to eq("done")
    expect(events).to eq(["still there?"]) # background reply delivered via event
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end
