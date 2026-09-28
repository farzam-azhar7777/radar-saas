require "test_helper"

class StuckGenerationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def posting(queued_at:, **over)
    JobPosting.create!({ upwork_id: SecureRandom.hex(6), title: "Rails dev", status: "matched",
                         score: 80, generation_queued_at: queued_at }.merge(over))
  end

  def long_ago = (Radar.generation_timeout + 600).seconds.ago

  test "a recently queued job still reads as writing" do
    assert posting(queued_at: 1.minute.ago).generating?
  end

  test "a job queued longer than it could possibly run is not writing" do
    p = posting(queued_at: long_ago)
    assert_not p.generating?, "the spinner must stop lying once the deadline passes"
    assert p.generation_stale?
  end

  test "a finished proposal is never writing, however old the flag" do
    p = posting(queued_at: 10.days.ago)
    p.proposals.create!(version: 1, body: "done")
    assert_not p.reload.generating?
    assert_not p.reload.generation_stale?
  end

  test "the sweep clears an abandoned generation" do
    p = posting(queued_at: long_ago)
    ReapStuckGenerationsJob.perform_now
    assert_nil p.reload.generation_queued_at
  end

  test "the sweep never re-queues, because a generation costs money" do
    posting(queued_at: long_ago)
    assert_no_enqueued_jobs(only: GenerateProposalJob) { ReapStuckGenerationsJob.perform_now }
  end

  test "the sweep leaves a live generation alone" do
    p = posting(queued_at: 30.seconds.ago)
    ReapStuckGenerationsJob.perform_now
    assert_not_nil p.reload.generation_queued_at
  end

  test "the sweep leaves finished work alone" do
    p = posting(queued_at: 10.days.ago)
    p.proposals.create!(version: 1, body: "done", generated_at: Time.current)
    ReapStuckGenerationsJob.perform_now
    assert_not_nil p.reload.generation_queued_at, "a proposal newer than the request means it finished"
  end

  # A rewrite runs on a posting that already has a proposal. Keying "finished"
  # off the mere existence of one left a dead rewrite flagged as running forever.
  test "a rewrite reads as writing even though an older proposal is on screen" do
    p = posting(queued_at: nil)
    p.proposals.create!(version: 1, body: "v1", generated_at: 2.hours.ago)
    p.update!(generation_queued_at: 30.seconds.ago)
    assert p.reload.generating?, "the pane must be able to say a rewrite is running"
  end

  test "a rewrite stops reading as writing once the new version lands" do
    p = posting(queued_at: 30.seconds.ago)
    p.proposals.create!(version: 1, body: "v1", generated_at: 2.hours.ago)
    assert p.reload.generating?
    p.proposals.create!(version: 2, body: "v2", generated_at: Time.current)
    assert_not p.reload.generating?
  end

  test "the sweep clears a rewrite that died, not just a first draft" do
    p = posting(queued_at: long_ago)
    p.proposals.create!(version: 1, body: "v1", generated_at: (Radar.generation_timeout + 900).seconds.ago)
    ReapStuckGenerationsJob.perform_now
    assert_nil p.reload.generation_queued_at
    assert_not p.reload.generating?
  end

  test "a generation failure clears the flag so it does not read as writing" do
    p = posting(queued_at: 1.minute.ago)
    p.update!(status: "generation_failed", generation_queued_at: nil)
    assert_not p.generating?
  end

  test "the tick sweeps on every run" do
    p = posting(queued_at: long_ago)
    PollTickJob.new.perform
    assert_nil p.reload.generation_queued_at
  end
end
