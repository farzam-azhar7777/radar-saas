class AddProposalStrategy < ActiveRecord::Migration[8.1]
  def change
    # Which shape the proposal was written in, and what the automated checks said.
    add_column :proposals, :archetype, :string
    add_column :proposals, :checks, :json, default: {}
    add_column :proposals, :attempts, :integer, null: false, default: 1

    # Lessons are scoped to the thing they are actually about: a whole archetype,
    # one search, or Farzam's voice everywhere.
    add_column :lessons, :archetype, :string
    add_index  :lessons, :archetype

    # What happened after he sent it. This is the only signal that tells us which
    # archetypes actually win, rather than which ones read nicely.
    add_column :job_postings, :outcome, :string
    add_column :job_postings, :outcome_at, :datetime
    add_index  :job_postings, :outcome
  end
end
