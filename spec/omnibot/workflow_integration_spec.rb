RSpec.describe "Order payment end-to-end" do
  include Omnibot::Testing::Helpers
  include ActiveJob::TestHelper

  before { Omnibot::Testing.fake! }
  after  { Omnibot::Testing.reset!; clear_enqueued_jobs }

  it "walks ask → extract → poll → done" do
    gateway = Queue.new
    %i[pending pending paid].each { |s| gateway << s }
    stub_const("FakeGateway", -> { gateway.pop })

    extractor = stub_const("ReceiptAgent", Class.new(Omnibot::Agent) { instructions "extract" })
    stub_agent(extractor).then_extract({ "amount" => 50_000, "method" => "bank transfer" })

    flow = stub_const("OrderPaymentWorkflow", Class.new(Omnibot::Workflow) do
      state :amount, :method, :paid

      step :ask_for_receipt do
        reply "Please upload your payment receipt"
        wait_for_input
      end

      step :verify_receipt do
        receipt = ReceiptAgent.extract(input, schema: Class.new)
        state.amount = receipt[:amount]
        state.method = receipt[:method]
      end

      step :watch_payment, poll: { every: 60, max_attempts: 5 } do
        status = FakeGateway.call
        poll_again if status == :pending
        state.paid = (status == :paid)
      end

      transition from: :ask_for_receipt, to: :verify_receipt
      transition from: :verify_receipt, to: :watch_payment, if: -> { state.amount.to_i > 0 }
      transition from: :verify_receipt, to: :ask_for_receipt
      transition from: :watch_payment, to: :done, if: -> { state.paid }
      transition from: :watch_payment, to: :failed
    end)

    run = flow.start(state: {})
    expect(run.replies).to eq(["Please upload your payment receipt"])

    run = flow.resume(run, input: "receipt: paid 50rb by bank transfer")
    expect(run.reload.current_step).to eq("watch_payment")
    expect(run.state["amount"]).to eq(50_000)

    2.times { perform_enqueued_jobs }
    expect(run.reload.status).to eq("done")
    expect(run.state["paid"]).to eq(true)
  end
end
