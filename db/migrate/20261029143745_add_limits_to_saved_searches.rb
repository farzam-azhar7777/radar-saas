class AddLimitsToSavedSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :saved_searches, :limits, :json, default: {}, null: false
  end
end
