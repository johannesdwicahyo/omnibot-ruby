RSpec.describe "Deposit check end-to-end" do
  include Omnibot::Testing::Helpers
  include ActiveJob::TestHelper

  before { Omnibot::Testing.fake! }
  after  { Omnibot::Testing.reset!; clear_enqueued_jobs }

  it "walks ask → extract → poll → done" do
    gateway = Queue.new
    %i[pending pending paid].each { |s| gateway << s }
    stub_const("FakeGateway", -> { gateway.pop })

    extractor = stub_const("ProofAgent", Class.new(Omnibot::Agent) { instructions "extract" })
    stub_agent(extractor).then_extract({ "amount" => 50_000, "bank" => "BCA" })

    flow = stub_const("DepositCheckWorkflow", Class.new(Omnibot::Workflow) do
      state :amount, :bank, :paid

      step :ask_for_proof do
        reply "Please upload your transfer receipt"
        wait_for_input
      end

      step :extract_proof do
        proof = ProofAgent.extract(input, schema: Class.new)
        state.amount = proof[:amount]
        state.bank = proof[:bank]
      end

      step :watch_gateway, poll: { every: 60, max_attempts: 5 } do
        status = FakeGateway.call
        poll_again if status == :pending
        state.paid = (status == :paid)
      end

      transition from: :ask_for_proof, to: :extract_proof
      transition from: :extract_proof, to: :watch_gateway, if: -> { state.amount.to_i > 0 }
      transition from: :extract_proof, to: :ask_for_proof
      transition from: :watch_gateway, to: :done, if: -> { state.paid }
      transition from: :watch_gateway, to: :failed
    end)

    run = flow.start(state: {})
    expect(run.replies).to eq(["Please upload your transfer receipt"])

    run = flow.resume(run, input: "receipt: transfer 50rb BCA")
    expect(run.reload.current_step).to eq("watch_gateway")
    expect(run.state["amount"]).to eq(50_000)

    2.times { perform_enqueued_jobs }
    expect(run.reload.status).to eq("done")
    expect(run.state["paid"]).to eq(true)
  end
end
