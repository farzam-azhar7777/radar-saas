class CreateJobPostings < ActiveRecord::Migration[8.1]
  def change
    create_table :job_postings do |t|
      t.string  :upwork_id, null: false
      t.string  :ciphertext
      t.string  :title, null: false
      t.text    :description
      t.string  :contract_type
      t.decimal :hourly_min, precision: 10, scale: 2
      t.decimal :hourly_max, precision: 10, scale: 2
      t.decimal :fixed_amount, precision: 12, scale: 2
      t.string  :client_country
      t.boolean :client_payment_verified
      t.decimal :client_total_spent, precision: 12, scale: 2
      t.integer :client_total_hires
      t.decimal :client_rating, precision: 3, scale: 2
      t.json    :skills, default: []
      t.datetime :published_at
      t.json    :raw_payload, default: {}
      t.references :saved_search, foreign_key: true
      t.integer :score
      t.json    :score_reasons, default: []
      t.string  :status, null: false, default: "new"
      t.datetime :applied_at
      t.string  :rate_proposed
      t.string  :job_url
      t.timestamps
    end
    add_index :job_postings, :upwork_id, unique: true
    add_index :job_postings, [ :status, :published_at ]
  end
end
