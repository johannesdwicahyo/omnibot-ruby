require "active_record"

# ponytail: guarded so re-`load`ing this file (e.g. to recreate the schema on
# a connection a spec already established, like a tempfile db for concurrency
# testing) doesn't stomp that connection back to :memory:. First load (from
# spec_helper, before any connection exists) still defaults to :memory:.
# `connected?` only reports true once a connection has actually been checked
# out, so check pool *existence* instead (raises before any establish_connection).
already_established = begin
  ActiveRecord::Base.connection_pool && true
rescue ActiveRecord::ConnectionNotDefined
  false
end
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:") unless already_established

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :omnibot_workflow_runs, force: true do |t|
    t.string   :type, null: false
    t.string   :status, null: false
    t.string   :current_step
    t.json     :state, default: {}
    t.integer  :attempts, default: 0, null: false
    t.datetime :step_entered_at
    t.integer  :timer_token, default: 0, null: false
    t.string   :ref_type
    t.bigint   :ref_id
    t.text     :error
    t.timestamps
  end
  add_index :omnibot_workflow_runs, [:ref_type, :ref_id]
  add_index :omnibot_workflow_runs, :status
  add_index :omnibot_workflow_runs, [:type, :status]
end
