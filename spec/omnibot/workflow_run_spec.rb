RSpec.describe Omnibot::WorkflowRun do
  it "creates with a type column without STI interference" do
    run = described_class.create!(type: "SomeWorkflow", status: "running",
                                  current_step: "start", state: { "a" => 1 })
    expect(run.reload.type).to eq("SomeWorkflow")
    expect(run.state).to eq({ "a" => 1 })
  end

  it "knows active vs terminal statuses" do
    run = described_class.new(status: "waiting_for_input")
    expect(run).to be_active
    run.status = "expired"
    expect(run).to be_terminal
  end

  it "defaults attempts and timer_token to 0 and replies to []" do
    run = described_class.create!(type: "W", status: "running", current_step: "s")
    expect(run.attempts).to eq(0)
    expect(run.timer_token).to eq(0)
    expect(run.replies).to eq([])
  end

  it "resolves workflow_class from type" do
    stub_const("MyFlow", Class.new)
    run = described_class.new(type: "MyFlow")
    expect(run.workflow_class).to eq(MyFlow)
  end
end
