class AddMovedBackToJobPostings < ActiveRecord::Migration[8.1]
  def change
    add_column :job_postings, :moved_back_at, :datetime
    add_column :job_postings, :passed_over_for, :json
    add_index :job_postings, :moved_back_at
  end
end
