class AddClientDetailsToJobPostings < ActiveRecord::Migration[8.1]
  def change
    add_column :job_postings, :client_city, :string
    add_column :job_postings, :client_timezone, :string
    add_column :job_postings, :client_total_posted_jobs, :integer
    add_column :job_postings, :client_total_reviews, :integer
    add_column :job_postings, :client_last_contract_title, :string
    add_column :job_postings, :client_financial_privacy, :boolean
  end
end
