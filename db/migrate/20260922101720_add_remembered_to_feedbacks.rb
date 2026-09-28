class AddRememberedToFeedbacks < ActiveRecord::Migration[8.1]
  def change
    add_column :feedbacks, :remembered, :boolean, default: false, null: false
  end
end
