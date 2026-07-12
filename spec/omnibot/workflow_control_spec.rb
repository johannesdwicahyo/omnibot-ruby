RSpec.describe "Workflow control operations" do
  let(:flow) do
    stub_const("EscFlow", Class.new(Omnibot::Workflow) do
      state :tries, :fixed
      step(:risky) do
        state.tries = (state.tries || 0) + 1
        raise "boom" unless state.fixed
        handover! reason: "manual check"
      end
      transition from: :risky, to: :done
    end)
  end

  it "handover! parks the run as waiting_for_human" do
    run = flow.start(state: { fixed: true })
    expect(run.status).to eq("waiting_for_human")
    expect(run.current_step).to eq("risky")
  end

  it "resume_from_human re-enters the current step as a fresh attempt" do
    run = flow.start(state: { fixed: true })
    run.resume_from_human
    # re-entering :risky raises handover! again — still waiting, attempts grew
    expect(run.status).to eq("waiting_for_human")
    expect(run.reload.state["tries"]).to eq(2)
    expect(run.attempts).to eq(2)
  end

  it "retry! re-enters a failed run's current step" do
    run = flow.start
    expect(run.status).to eq("failed")
    run.state = run.state.merge("fixed" => true)
    run.save!
    run.retry!
    expect(run.status).to eq("waiting_for_human")
    expect(run.error).to be_nil
  end

  it "retry! refuses non-failed runs" do
    run = flow.start(state: { fixed: true })
    expect { run.retry! }.to raise_error(Omnibot::WorkflowError::StaleResume)
  end

  it "cancel! moves any active run to cancelled and refuses terminal ones" do
    run = flow.start(state: { fixed: true })
    run.cancel!
    expect(run.status).to eq("cancelled")
    expect { run.cancel! }.to raise_error(Omnibot::WorkflowError::StaleResume)
  end
end
