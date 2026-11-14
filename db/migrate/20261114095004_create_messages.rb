class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :job_posting, null: false, foreign_key: true
      t.string :role, null: false
      t.text :body, null: false
      t.text :note
      t.json :claude_meta, default: {}
      t.timestamps
    end

    add_column :job_postings, :conversation_session_id, :string
    add_column :job_postings, :reply_queued_at, :datetime
    add_column :job_postings, :reply_error, :text
  end
end
