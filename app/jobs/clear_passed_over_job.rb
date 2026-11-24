class ClearPassedOverJob < ApplicationJob
  queue_as :default

  KEEP = 7.days

  def perform
    JobPosting.where(status: "ignored", created_at: ...KEEP.ago)
              .where.missing(:proposals, :messages)
              .where.not(id: Feedback.where.not(job_posting_id: nil).select(:job_posting_id))
              .find_each(&:destroy)
  end
end
