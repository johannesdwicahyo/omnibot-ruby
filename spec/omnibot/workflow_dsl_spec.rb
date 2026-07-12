RSpec.describe Omnibot::Workflow do
  let(:klass) do
    Class.new(described_class) do
      state :order_id, :verified
      step(:ask)    { }
      step(:watch, poll: { every: 60, max_attempts: 10 }) { }
      transition from: :ask, to: :watch, if: -> { true }
      transition from: :ask, to: :done
      timeout :ask, after: 1800, to: :expired
      on_complete { :hooked }
      while_running :ignore
    end
  end

  it "stores steps in declaration order with poll config" do
    expect(klass.steps.keys).to eq(%i[ask watch])
    expect(klass.steps[:watch][:poll]).to eq(every: 60, max_attempts: 10)
  end

  it "stores transitions in order and timeouts by step" do
    expect(klass.transitions.map { |t| t[:to] }).to eq(%i[watch done])
    expect(klass.timeouts[:ask]).to include(after: 1800, to: :expired)
  end

  it "records state keys, on_complete and while_running" do
    expect(klass.state_keys).to eq(%i[order_id verified])
    expect(klass.on_complete_hook.call).to eq(:hooked)
    expect(klass.while_running).to eq(:ignore)
  end

  it "defaults while_running to :ignore and rejects unknown modes" do
    expect(Class.new(described_class).while_running).to eq(:ignore)
    expect {
      Class.new(described_class) { while_running :queue }
    }.to raise_error(ArgumentError, /while_running/)
  end

  it "deep-copies DSL state to subclasses" do
    child = Class.new(klass) { step(:extra) { } }
    expect(child.steps.keys).to eq(%i[ask watch extra])
    expect(klass.steps.keys).to eq(%i[ask watch])
  end
end
