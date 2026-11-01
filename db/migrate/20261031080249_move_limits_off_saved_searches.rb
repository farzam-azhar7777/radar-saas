class MoveLimitsOffSavedSearches < ActiveRecord::Migration[8.1]
  def change
    remove_column :saved_searches, :limits, :json, default: {}, null: false
    remove_column :saved_searches, :min_hourly, :decimal, precision: 10, scale: 2
    remove_column :saved_searches, :min_fixed, :decimal, precision: 12, scale: 2
  end
end
