class AddLiveFieldsAndLearning < ActiveRecord::Migration[8.1]
  def change
    # --- fields the live API actually gives us, verified 2026-09-08 ---
    change_table :job_postings, bulk: true do |t|
      t.integer  :total_applicants          # live competition count
      t.boolean  :already_applied, default: false, null: false
      t.string   :engagement                # "Less than 30 hrs/week"
      t.string   :duration_label            # "1 to 3 months"
      t.string   :category
      t.string   :subcategory
      t.string   :experience_level
      t.boolean  :premium, default: false, null: false
      t.boolean  :enterprise, default: false, null: false
      t.integer  :freelancers_to_hire
      t.json     :preferred_locations, default: []
      t.boolean  :preferred_location_mandatory, default: false, null: false
      t.json     :screening_questions, default: []
      t.boolean  :cover_letter_required
      t.datetime :detail_fetched_at
    end

    # Tier A searches write a proposal the moment a match lands. Tier B only
    # notify, and Farzam presses Generate if he wants one.
    add_column :saved_searches, :auto_generate, :boolean, default: false, null: false
    add_column :saved_searches, :position, :integer, default: 0, null: false

    # --- the learning loop ---
    create_table :feedbacks do |t|
      t.references :job_posting, foreign_key: true
      t.references :proposal, foreign_key: true
      t.references :saved_search, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end

    # A durable rule distilled from one or more pieces of feedback. Injected
    # into every future generation, so the writing improves rather than
    # repeating the same mistake.
    create_table :lessons do |t|
      t.references :saved_search, foreign_key: true   # null means it applies everywhere
      t.text    :body, null: false
      t.text    :source_feedback
      t.boolean :active, null: false, default: true
      t.integer :times_used, null: false, default: 0
      t.timestamps
    end
    add_index :lessons, :active
  end
end
