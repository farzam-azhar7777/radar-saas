# One named part of a proposal: the opening, an answer, the skills block.
#
# The names are chosen by whoever wrote the proposal, per job, because the
# right shape for a scoped Rails migration is not the right shape for a vague
# one-liner. Only the role is constrained, and only because the assembler has
# to know where a part goes.
class ProposalSection < ApplicationRecord
  belongs_to :proposal

  ROLES = ProposalSectioner::ROLES

  validates :label, presence: true
  validates :role, inclusion: { in: ROLES }

  scope :ordered, -> { order(:position, :id) }

  # A rewrite is in flight until the section is replaced by the one on the new
  # version. Bounded by the same timeout the generator uses, so a crashed job
  # cannot leave a card spinning forever.
  def rewriting?
    rewrite_queued_at.present? && rewrite_queued_at > Radar.generation_timeout.seconds.ago
  end

  def rewriting_for = rewrite_queued_at ? (Time.current - rewrite_queued_at).to_i : 0

  def word_count = body.to_s.split(/\s+/).reject(&:blank?).size

  def answer? = role == "answer"
  def portfolio? = role == "portfolio"

  # What this part is called on screen, and in the rewrite prompt.
  def display_label = label.presence || role.humanize

  def cost_usd = rewrite_meta.is_a?(Hash) ? rewrite_meta["total_cost_usd"] : nil
end
