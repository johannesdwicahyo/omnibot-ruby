require "tempfile"

RSpec.describe "Workflow concurrency" do
  it "executes the resumed step exactly once across racing threads" do
    db = Tempfile.new(["omnibot_conc", ".sqlite3"])
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: db.path,
                                            pool: 5, timeout: 5000)
    load File.expand_path("../support/active_record.rb", __dir__)
    # the support file's Schema.define(force: true) recreates the table on
    # whichever connection is current — here the tempfile DB
    counter = Queue.new
    flow = stub_const("RaceFlow", Class.new(Omnibot::Workflow) do
      step(:ask) { wait_for_input }
      step(:once) { sleep 0.05; COUNTER << 1 }
      transition from: :ask, to: :once
      transition from: :once, to: :done
    end)
    stub_const("COUNTER", counter)

    run = flow.start
    threads = 2.times.map do
      Thread.new do
        flow.resume(Omnibot::WorkflowRun.find(run.id), input: "go")
      rescue ActiveRecord::StatementInvalid, Omnibot::WorkflowError::StaleResume
        :lost
      end
    end
    threads.each(&:join)

    expect(counter.size).to eq(1)
    expect(run.reload.status).to eq("done")
  ensure
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    load File.expand_path("../support/active_record.rb", __dir__)
    db&.close!
  end
end
