class CreateProposalSections < ActiveRecord::Migration[8.1]
  def change
    create_table :proposal_sections do |t|
      t.references :proposal, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :label, null: false
      t.string :role, null: false, default: "letter"
      t.text :body, null: false, default: ""
      t.datetime :rewrite_queued_at
      t.text :rewrite_feedback
      t.integer :rewrite_duration_ms
      t.json :rewrite_meta, default: {}
      t.timestamps
    end

    add_index :proposal_sections, [ :proposal_id, :position ]
  end
end
