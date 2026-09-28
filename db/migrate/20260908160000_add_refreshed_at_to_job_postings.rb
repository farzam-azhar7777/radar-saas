class AddRefreshedAtToJobPostings < ActiveRecord::Migration[8.1]
  def change
    add_column :job_postings, :refreshed_at, :datetime
    add_column :job_postings, :applicants_at_discovery, :integer
  end
end
