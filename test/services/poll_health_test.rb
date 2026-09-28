require "test_helper"

# Polling stopped at 02:19 on 2026-09-16 and nothing noticed for nine hours.
# The laptop slept, solid_queue pruned the scheduler's registration, and the
# scheduler process stayed alive as an orphan: running, unregistered, enqueuing
# nothing. Every other process was healthy and the only symptom was an inbox
# that quietly stopped filling.
class PollHealthTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Setting.where(key: PollTickJob::LAST_TICK_AT).delete_all
    Setting.where(key: PollHealth::REVIVED_AT).delete_all
  end

  def tick_at(time) = Setting.set(PollTickJob::LAST_TICK_AT, time.iso8601)

  test "a recent tick is healthy" do
    tick_at(30.seconds.ago)
    assert_not PollHealth.stalled?
  end

  test "ten minutes of silence is a stall, not jitter" do
    tick_at(11.minutes.ago)
    assert PollHealth.stalled?
    assert_match "not arriving", PollHealth.message
  end

  test "never having run counts as stalled" do
    assert PollHealth.stalled?
  end

  # The workers stay alive when the scheduler dies, so anything reaching the
  # database can keep polling going.
  test "a stall enqueues a tick directly" do
    tick_at(11.minutes.ago)
    assert_enqueued_with(job: PollTickJob) { assert PollHealth.revive! }
  end

  test "a healthy scheduler is never second-guessed" do
    tick_at(30.seconds.ago)
    assert_no_enqueued_jobs(only: PollTickJob) { assert_not PollHealth.revive! }
  end

  # A deadman switch, not a second scheduler. The alerts tab calls this every
  # 30 seconds and must not queue a tick each time.
  test "reviving is rate limited" do
    tick_at(11.minutes.ago)
    assert PollHealth.revive!
    assert_no_enqueued_jobs(only: PollTickJob) { assert_not PollHealth.revive! }
  end

  test "a tick records that it ran" do
    travel_to Time.current do
      PollTickJob.new.perform
      assert_not PollHealth.stalled?, "having just ticked, it cannot be stalled"
    end
  end
end
