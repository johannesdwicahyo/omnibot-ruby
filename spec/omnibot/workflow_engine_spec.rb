RSpec.describe "Workflow engine core" do
  before do
    stub_const("TRACE", [])
  end

  it "runs steps through first-match transitions to done" do
    flow = stub_const("LinearFlow", Class.new(Omnibot::Workflow) do
      state :score
      step(:a) { TRACE << :a; state.score = 5 }
      step(:b) { TRACE << :b }
      transition from: :a, to: :done, if: -> { state.score > 10 }
      transition from: :a, to: :b
      transition from: :b, to: :done
    end)
    run = flow.start
    expect(TRACE).to eq(%i[a b])
    expect(run.status).to eq("done")
    expect(run.reload.state["score"]).to eq(5)
  end

  it "treats a step with no outgoing transitions as terminal (done)" do
    flow = stub_const("OneStep", Class.new(Omnibot::Workflow) do
      step(:only) { TRACE << :only }
    end)
    expect(flow.start.status).to eq("done")
  end

  it "fails with a clear error when transitions exist but none match" do
    flow = stub_const("DeadEnd", Class.new(Omnibot::Workflow) do
      step(:a) { }
      transition from: :a, to: :done, if: -> { false }
    end)
    run = flow.start
    expect(run.status).to eq("failed")
    expect(run.error).to eq("no transition matched from :a")
  end

  it "counts attempts per step entry, resetting on a different step" do
    flow = stub_const("LoopFlow", Class.new(Omnibot::Workflow) do
      state :tries
      step(:retryable) { state.tries = attempts }
      step(:after) { TRACE << attempts }
      transition from: :retryable, to: :after, if: -> { attempts >= 3 }
      transition from: :retryable, to: :retryable
      transition from: :after, to: :done
    end)
    run = flow.start
    expect(run.reload.state["tries"]).to eq(3)
    expect(TRACE).to eq([1]) # attempts reset entering :after
  end

  it "marks failed and stores the error when a step raises" do
    flow = stub_const("BoomFlow", Class.new(Omnibot::Workflow) do
      step(:boom) { raise "kaput" }
      transition from: :boom, to: :done
    end)
    run = flow.start
    expect(run.status).to eq("failed")
    expect(run.error).to eq("kaput")
    expect(run.current_step).to eq("boom")
  end

  it "runs on_complete before status flips to done" do
    order = []
    flow = stub_const("HookFlow", Class.new(Omnibot::Workflow) do
      step(:only) { }
    end)
    flow.on_complete { order << run.status }
    run = flow.start
    expect(order).to eq(["running"])
    expect(run.status).to eq("done")
  end

  it "seeds initial state and exposes declared accessors" do
    flow = stub_const("SeedFlow", Class.new(Omnibot::Workflow) do
      state :order_id
      step(:only) { TRACE << state.order_id }
    end)
    flow.start(state: { order_id: 123 })
    expect(TRACE).to eq([123])
  end

  it "increments timer_token on every step entry" do
    flow = stub_const("TokenFlow", Class.new(Omnibot::Workflow) do
      step(:a) { }
      step(:b) { }
      transition from: :a, to: :b
      transition from: :b, to: :done
    end)
    expect(flow.start.timer_token).to eq(2)
  end

  it "includes status alongside error in the omnibot.workflow.step event when a step raises" do
    flow = stub_const("BoomEventFlow", Class.new(Omnibot::Workflow) do
      step(:boom) { raise "kaput on the error path" }
      transition from: :boom, to: :done
    end)
    events = []
    ActiveSupport::Notifications.subscribed(->(*a) { events << a.last }, "omnibot.workflow.step") do
      flow.start
    end
    expect(events.last).to include(error: "kaput on the error path", status: "failed")
  end

  it "records failure instead of raising when an on_complete hook raises" do
    flow = stub_const("BadHookFlow", Class.new(Omnibot::Workflow) do
      step(:only) { }
    end)
    flow.on_complete { raise "hook exploded" }
    run = nil
    expect { run = flow.start }.not_to raise_error
    expect(run.status).to eq("failed")
    expect(run.error).to match(/on_complete hook raised/)
  end

  it "caps steps per activation to stop an unconditional self-loop from spinning forever" do
    flow = stub_const("SelfLoopFlow", Class.new(Omnibot::Workflow) do
      step(:a) { }
      step(:b) { }
      transition from: :a, to: :b
      transition from: :b, to: :a
    end)
    run = nil
    expect { run = flow.start }.not_to raise_error
    expect(run.status).to eq("failed")
    expect(run.error).to match(/transition loop/)
  end
end
