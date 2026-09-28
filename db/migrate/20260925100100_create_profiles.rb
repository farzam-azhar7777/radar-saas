# The one person this install belongs to. Everything a prompt used to say
# about Farzam by name is read from here instead.
class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.string :full_name
      t.string :preferred_name
      t.string :title
      t.string :email
      t.string :country
      t.string :city
      t.string :timezone
      t.decimal :hourly_rate, precision: 8, scale: 2
      t.integer :hours_per_week
      t.string :response_time
      t.string :availability
      t.integer :years_experience
      t.text :languages
      t.string :upwork_url
      t.string :github_url
      t.text :github_note
      t.string :linkedin_url
      t.string :website_url
      t.string :portfolio_url
      t.text :credentials_line
      t.text :summary
      t.text :winning_opening
      t.string :winning_opening_context
      t.text :signature
      t.json :voice_samples, default: []
      t.timestamps
    end
  end
end
