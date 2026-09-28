class AddGenerationQueuedAtToJobPostings < ActiveRecord::Migration[8.1]
  def change
    add_column :job_postings, :generation_queued_at, :datetime
  end
end
