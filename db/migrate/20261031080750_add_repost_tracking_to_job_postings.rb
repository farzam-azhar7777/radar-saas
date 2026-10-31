class AddRepostTrackingToJobPostings < ActiveRecord::Migration[8.1]
  def change
    add_reference :job_postings, :repost_of, foreign_key: { to_table: :job_postings }, index: true
    add_column :job_postings, :repost_count, :integer, default: 0, null: false
    add_index :job_postings, %i[client_country created_at]
  end
end
