# The knowledge base: which of the person's repositories are theirs, what they
# did in each, and the project write-ups built from that evidence.
#
# A scan is one projects folder. Repos are git roots found in it. Projects are
# what a client would call a product, clustered from one or more repos. Only
# accepted projects are written into the career folder.
class CreateKnowledge < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_scans do |t|
      t.string :root_path, null: false
      t.string :status, null: false, default: "discovering"
      t.json :candidates, default: []
      t.json :identities, default: []
      t.json :names, default: []
      t.integer :progress_done, default: 0
      t.integer :progress_total, default: 0
      t.string :progress_label
      t.text :error
      t.datetime :inventoried_at
      t.timestamps
    end

    create_table :knowledge_projects do |t|
      t.references :knowledge_scan, foreign_key: true
      t.string :name, null: false
      t.string :stem
      t.string :slug
      t.string :status, null: false, default: "candidate"
      t.boolean :included, null: false, default: false
      t.boolean :manual, null: false, default: false
      t.float :rank_score, default: 0
      t.integer :own_commits, default: 0
      t.integer :total_commits, default: 0
      t.integer :own_commits_when_written
      t.datetime :first_at
      t.datetime :last_at
      t.string :client
      t.string :url
      t.text :note
      t.text :draft_yaml
      t.json :open_questions, default: []
      t.json :meta, default: {}
      t.text :error
      t.integer :position
      t.datetime :queued_at
      t.datetime :drafted_at
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :knowledge_projects, [ :knowledge_scan_id, :stem ]
    add_index :knowledge_projects, :status

    create_table :knowledge_repos do |t|
      t.references :knowledge_scan, null: false, foreign_key: true
      t.references :knowledge_project, foreign_key: true
      t.string :path, null: false
      t.string :name, null: false
      t.string :head_sha
      t.integer :total_commits, default: 0
      t.integer :own_commits, default: 0
      t.datetime :first_at
      t.datetime :last_at
      t.datetime :first_own_at
      t.datetime :last_own_at
      t.integer :active_months, default: 0
      t.integer :lines_added, default: 0
      t.integer :lines_removed, default: 0
      t.integer :file_count, default: 0
      t.string :remote_url
      t.text :readme_head
      t.json :stack, default: {}
      t.json :tables, default: []
      t.json :top_dirs, default: {}
      t.json :top_files, default: []
      t.string :inventory_key
      t.text :error
      t.timestamps
    end
    add_index :knowledge_repos, [ :knowledge_scan_id, :path ], unique: true
  end
end
