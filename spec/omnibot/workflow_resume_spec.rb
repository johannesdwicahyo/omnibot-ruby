RSpec.describe "Workflow resume" do
  let(:flow) do
    stub_const("AskFlow", Class.new(Omnibot::Workflow) do
      state :answer
      step(:ask) do
        reply "What is your order id?"
        wait_for_input
      end
      step(:record) { state.answer = input }
      transition from: :ask, to: :record
      transition from: :record, to: :done
    end)
  end

  it "checkpoints at wait_for_input and exposes replies" do
    run = flow.start
    expect(run.status).to eq("waiting_for_input")
    expect(run.current_step).to eq("ask")
    expect(run.replies).to eq(["What is your order id?"])
  end

  it "never executes statements after wait_for_input" do
    leaked = []
    f = stub_const("LeakFlow", Class.new(Omnibot::Workflow) do
      step(:ask) { wait_for_input; leaked << :ran }
      transition from: :ask, to: :done
    end)
    f.start
    expect(leaked).to be_empty
  end

  it "resume feeds input to the next step and continues to done" do
    run = flow.start
    run = flow.resume(run, input: "ORDER-9")
    expect(run.status).to eq("done")
    expect(run.reload.state["answer"]).to eq("ORDER-9")
  end

  it "exposes input to transition conditions" do
    f = stub_const("CondFlow", Class.new(Omnibot::Workflow) do
      step(:ask) { wait_for_input }
      step(:yes) { }
      step(:no)  { }
      transition from: :ask, to: :yes, if: -> { input == "yes" }
      transition from: :ask, to: :no
      transition from: :yes, to: :done
      transition from: :no, to: :done
    end)
    run = f.start
    f.resume(run, input: "yes")
    expect(run.reload.current_step).to eq("yes").or eq("done")
    expect(run.status).to eq("done")
  end

  it "resets replies per activation" do
    run = flow.start
    expect(run.replies.length).to eq(1)
    flow.resume(run, input: "x")
    expect(run.replies).to eq([]) # record step sends nothing
  end

  it "ignores resume while running (while_running :ignore)" do
    run = flow.start
    run.update!(status: "running")
    expect(flow.resume(run, input: "x").status).to eq("running")
  end

  it "raises NotImplementedError for while_running :interrupt" do
    f = stub_const("IntFlow", Class.new(Omnibot::Workflow) do
      while_running :interrupt
      step(:a) { wait_for_input }
      transition from: :a, to: :done
    end)
    run = f.start
    run.update!(status: "running")
    expect { f.resume(run, input: "x") }
      .to raise_error(NotImplementedError, /v0\.3/)
  end

  it "raises StaleResume on terminal runs" do
    run = flow.start
    flow.resume(run, input: "x")
    expect { flow.resume(run, input: "again") }
      .to raise_error(Omnibot::WorkflowError::StaleResume)
  end
end
