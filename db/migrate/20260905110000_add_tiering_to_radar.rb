class AddTieringToRadar < ActiveRecord::Migration[8.1]
  def change
    # Score at or above which a match is "hot": notify instantly and generate.
    add_column :saved_searches, :hot_threshold, :integer, null: false, default: 85

    # When Farzam was told about this posting. Nil means it is waiting for a digest.
    add_column :job_postings, :notified_at, :datetime
    add_index  :job_postings, :notified_at

    # Upwork allows 40,000 requests a day. We count our own.
    create_table :api_usages do |t|
      t.date    :on, null: false
      t.integer :requests, null: false, default: 0
      t.timestamps
    end
    add_index :api_usages, :on, unique: true
  end
end
