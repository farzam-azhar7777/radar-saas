# Secrets entered through the setup wizard. The value column is encrypted by
# Active Record with a key generated per install, so a fresh clone needs no
# master key and nothing secret ever lives in the repository.
class CreateCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :credentials do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :credentials, :key, unique: true
  end
end
