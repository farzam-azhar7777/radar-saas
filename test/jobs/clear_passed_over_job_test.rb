require "test_helper"

class ClearPassedOverJobTest < ActiveSupport::TestCase
  def job(status: "ignored", found: 8.days.ago, **over)
    JobPosting.create!({ upwork_id: SecureRandom.hex(6), title: "Rails dev", status: status, score: 40, created_at: found }.merge(over))
  end

  test "passed-over jobs older than a week are deleted, newer ones stay" do
    old = job
    recent = job(found: 6.days.ago)

    ClearPassedOverJob.perform_now

    assert_not JobPosting.exists?(old.id)
    assert JobPosting.exists?(recent.id)
  end

  test "old jobs in any other list stay" do
    kept = %w[matched applied dismissed].map { |status| job(status: status) }
    ClearPassedOverJob.perform_now
    assert_equal kept.size, JobPosting.where(id: kept).count
  end

  test "a passed-over job with a proposal, a conversation or feedback is kept" do
    written = job.tap { |j| j.proposals.create!(version: 1, body: "draft") }
    talked = job.tap { |j| j.messages.create!(role: "client", body: "Hi") }
    noted = job.tap { |j| Feedback.create!(job_posting: j, body: "too vague") }

    ClearPassedOverJob.perform_now

    assert_equal 3, JobPosting.where(id: [ written, talked, noted ]).count
  end

  test "a newer repost of a deleted job stays and stops pointing at it" do
    original = job
    repost = job(status: "matched", found: 1.day.ago, repost_of: original, repost_count: 1)

    ClearPassedOverJob.perform_now

    assert_nil repost.reload.repost_of_id
  end
end
