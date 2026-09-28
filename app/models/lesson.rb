# A durable writing rule learned from the person's feedback, injected into every
# future proposal it applies to.
#
# Scope is the thing the rule is actually about:
#   global    - their voice, applies everywhere
#   archetype - how a shape should be written (all high-competition posts, say)
#   search    - specific to a category of job
class Lesson < ApplicationRecord
  belongs_to :saved_search, optional: true

  validates :body, presence: true

  # A rule is injected into the prompt verbatim, so a dash in the rule teaches
  # the dash. Normalise on the way in.
  before_validation :plain_dashes

  def plain_dashes
    return if body.blank?

    self.body = body.gsub(/\s*[\u2014\u2013]\s*/, " - ").strip
  end

  scope :active, -> { where(active: true) }

  def self.for(saved_search: nil, archetype: nil)
    active.where(
      "(saved_search_id IS NULL AND archetype IS NULL) OR saved_search_id = :s OR archetype = :a",
      s: saved_search&.id, a: archetype
    ).order(:created_at)
  end

  def self.prompt_block(saved_search: nil, archetype: nil)
    rules = self.for(saved_search: saved_search, archetype: archetype).to_a
    return nil if rules.empty?

    rules.each { |r| r.increment!(:times_used) }
    lines = rules.map.with_index(1) { |l, i| "#{i}. #{l.body}" }
    "WHAT #{Profile.first_name.upcase} HAS CORRECTED BEFORE. Apply every one of these:\n#{lines.join("\n")}"
  end

  def scope_label
    return saved_search.name if saved_search
    return "Archetype #{archetype}" if archetype.present?

    "Every proposal"
  end
end
