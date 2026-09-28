# What Farzam said was wrong with a proposal, or wanted changed in general.
# Raw, in his words. Lessons are distilled from these; this table is the
# evidence trail.
#
# A note can become a rule, be judged too one-off to keep, or fail outright,
# and until now all three looked identical on screen: a note that simply never
# produced anything. The outcome is recorded so the page can say which happened
# and why, and so a skip can be overruled.
class Feedback < ApplicationRecord
  belongs_to :job_posting, optional: true
  belongs_to :proposal, optional: true
  belongs_to :saved_search, optional: true
  belongs_to :lesson, optional: true

  validates :body, presence: true
  scope :recent, -> { order(created_at: :desc) }

  PENDING = "pending".freeze  # the distiller is still running
  LEARNED = "learned".freeze  # it became a rule
  SKIPPED = "skipped".freeze  # judged too one-off, or already covered
  FAILED  = "failed".freeze   # the distiller errored or returned nothing

  # A rewrite note that was never meant to teach anything has no outcome.
  def tracked? = outcome.present?

  def learned? = outcome == LEARNED
  def skipped? = outcome == SKIPPED
  def failed?  = outcome == FAILED

  # Bounded, so a distiller killed mid-call does not leave a note reading as
  # still running for the rest of the week.
  def pending? = outcome == PENDING && created_at > 30.minutes.ago
  def stalled? = outcome == PENDING && created_at <= 30.minutes.ago

  # A skip or a failure can be overruled: the note becomes a rule verbatim.
  def keepable? = tracked? && !learned?

  def status_label
    return "Became a rule" if learned?
    return "Not kept" if skipped?
    return "Could not be read" if failed?
    return "Working on it" if pending?
    return "Gave up" if stalled?

    nil
  end
end
