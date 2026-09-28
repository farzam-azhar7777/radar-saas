class CreateProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :proposals do |t|
      t.references :job_posting, null: false, foreign_key: true
      t.integer :version, null: false, default: 1
      t.text    :body
      t.text    :feedback
      t.string  :template_name
      t.datetime :generated_at
      t.integer :duration_ms
      t.json    :claude_meta, default: {}
      t.timestamps
    end
    add_index :proposals, [ :job_posting_id, :version ], unique: true
  end
end
