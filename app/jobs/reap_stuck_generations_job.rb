# A worker killed mid-generation leaves the posting flagged as writing with no
# job left to finish it. SolidQueue prunes the dead process and raises from the
# supervisor, so no hook inside the job ever runs.
#
# This clears the flag and leaves the posting exactly where Farzam can decide
# for himself. It never re-queues: a generation costs real money, and silently
# retrying one he did not ask for is worse than showing him a button.
class ReapStuckGenerationsJob < ApplicationJob
  queue_as :default

  def perform
    # Not `where.missing(:proposals)`: a rewrite runs on a posting that already
    # has one, so the test is whether any proposal landed AFTER this request,
    # not whether any proposal exists at all.
    stuck = JobPosting.where.not(generation_queued_at: nil)
                      .where(generation_queued_at: ..JobPosting.generation_deadline)
                      .where.not(status: "generation_failed")
                      .where.not(
                        Proposal.where("proposals.job_posting_id = job_postings.id")
                                .where("COALESCE(proposals.generated_at, proposals.created_at) > job_postings.generation_queued_at")
                                .arel.exists
                      )

    return if stuck.empty?

    ids = stuck.pluck(:id)
    stuck.update_all(generation_queued_at: nil)
    Rails.logger.warn("[Reap] cleared #{ids.size} abandoned generation(s): #{ids.join(', ')}. Not re-queued.")
    ids
  end
end
