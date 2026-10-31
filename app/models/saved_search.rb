class SavedSearch < ApplicationRecord
  # Comma-separated mirrors of the json columns, used by the form only.
  attr_accessor :terms_text, :excluded_keywords_text

  has_many :job_postings, dependent: :nullify
  has_many :lessons, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :threshold, numericality: { in: 0..100 }
  validates :hot_threshold, numericality: { in: 0..100 }
  validate  { errors.add(:hot_threshold, "must be at or above the threshold") if hot_threshold.to_i < threshold.to_i }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }
  scope :auto_generating, -> { where(auto_generate: true) }

  # Must total 100. category_fit was carved mostly out of skill_overlap, which
  # was the largest source of false negatives: a post that describes its domain
  # rather than its stack scored zero there while Upwork had already classified
  # it correctly.
  DEFAULT_WEIGHTS = {
    "title_match"      => 25,
    "skill_overlap"    => 20,
    "category_fit"     => 10,
    "project_tags"     => 8,
    "budget"           => 15,
    "client_history"   => 10,
    "recency"          => 12
  }.freeze

  def effective_weights
    DEFAULT_WEIGHTS.merge(weights.presence || {})
  end

  def terms_list
    Array(terms).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def excluded_keywords_list
    Array(excluded_keywords).map(&:to_s).map(&:downcase)
  end

  # Tier A writes a proposal on arrival; Tier B waits for Farzam to ask.
  def tier = auto_generate? ? "Writes now" : "Notifies only"
end
