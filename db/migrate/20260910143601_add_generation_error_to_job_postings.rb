class AddGenerationErrorToJobPostings < ActiveRecord::Migration[8.1]
  def change
    add_column :job_postings, :generation_error, :text
  end
end
