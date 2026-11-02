class AddSourceToJobPostings < ActiveRecord::Migration[8.1]
  def change
    add_column :job_postings, :source, :string, default: "upwork", null: false
    add_index :job_postings, :source
  end
end
