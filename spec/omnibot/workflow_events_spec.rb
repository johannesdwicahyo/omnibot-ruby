RSpec.describe "Workflow instrumentation" do
  include ActiveJob::TestHelper
  after { clear_enqueued_jobs }

  it "emits step, transition, reply, and handover with documented payloads" do
    captured = Hash.new { |h, k| h[k] = [] }
    subs = %w[step transition reply handover timeout].map do |kind|
      ActiveSupport::Notifications.subscribe("omnibot.workflow.#{kind}") do |event|
        captured[kind] << event.payload
      end
    end

    flow = stub_const("EventFlow", Class.new(Omnibot::Workflow) do
      step(:greet) { reply "hi" }
      step(:park)  { handover! reason: "human please" }
      transition from: :greet, to: :park
      transition from: :park, to: :done
    end)
    run = flow.start

    expect(captured["step"].map { |p| p[:step] }).to eq(%i[greet park])
    expect(captured["step"].first).to include(workflow: flow, run_id: run.id, attempts: 1)
    expect(captured["transition"].first).to include(from: :greet, to: :park)
    expect(captured["reply"].first).to include(step: "greet", text: "hi")
    expect(captured["handover"].first).to include(reason: "human please")
  ensure
    subs.each { |s| ActiveSupport::Notifications.unsubscribe(s) }
  end

  it "carries the error in the step payload when a step raises" do
    payloads = []
    sub = ActiveSupport::Notifications.subscribe("omnibot.workflow.step") { |e| payloads << e.payload }
    flow = stub_const("ErrFlow", Class.new(Omnibot::Workflow) do
      step(:boom) { raise "nope" }
      transition from: :boom, to: :done
    end)
    flow.start
    expect(payloads.last[:error]).to eq("nope")
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end
