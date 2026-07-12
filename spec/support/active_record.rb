require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

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
