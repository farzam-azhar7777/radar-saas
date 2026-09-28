class CreateSavedSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_searches do |t|
      t.string  :name, null: false
      t.json    :terms, default: []
      t.string  :contract_type
      t.decimal :min_hourly, precision: 10, scale: 2
      t.decimal :min_fixed,  precision: 12, scale: 2
      t.json    :excluded_countries, default: []
      t.json    :excluded_keywords,  default: []
      t.string  :template_name
      t.integer :threshold, null: false, default: 70
      t.json    :weights, default: {}
      t.boolean :active, null: false, default: true
      t.datetime :last_polled_at
      t.timestamps
    end
    add_index :saved_searches, :name, unique: true
  end
end
