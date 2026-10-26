class AddClientHireStatsToJobPostings < ActiveRecord::Migration[8.1]
  def change
    add_column :job_postings, :client_jobs_with_hires, :integer
    add_column :job_postings, :client_open_jobs, :integer
  end
end
