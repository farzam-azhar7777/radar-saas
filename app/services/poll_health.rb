# Polling stopped at 02:19 and nobody noticed for nine hours.
#
# Nothing crashed. The laptop slept, solid_queue pruned the scheduler's
# registration for missing heartbeats, and the scheduler process stayed alive
# as an orphan: still running, no longer registered, no longer enqueuing
# anything. Every other process was healthy, the web app served fine, and the
# only symptom was an inbox that quietly stopped filling.
#
# The scheduler enqueues PollTickJob every minute, so the age of the newest
# tick is the honest signal. Posting age is not: the real cadence is 3 minutes
# awake and 20 overnight, jittered, and a quiet hour on Upwork looks identical
# to a dead scheduler.
module PollHealth
  module_function

  # Ticks are scheduled every minute. Ten minutes of silence is not jitter.
  STALL_AFTER = 10.minutes

  # A stalled scheduler leaves the workers alive and able to run whatever is
  # enqueued, so anything that can reach the database can keep polling going.
  # Rate limited: this is a deadman switch, not a second scheduler.
  REVIVE_EVERY = 3.minutes

  # PollTickJob stamps this every time it runs. Reading what actually ran beats
  # reading what was enqueued, and keeps health independent of solid_queue's
  # own tables, which live in a different database.
  def last_tick_at
    raw = Setting.get(PollTickJob::LAST_TICK_AT)
    raw.present? ? Time.zone.parse(raw) : nil
  rescue StandardError
    nil
  end

  def stalled?
    last = last_tick_at
    last.nil? || last < STALL_AFTER.ago
  end

  def stalled_for
    last = last_tick_at
    last && (Time.current - last)
  end

  def message
    minutes = (stalled_for.to_i / 60)
    return "Polling has never run." if stalled_for.nil?

    "No poll has run for #{minutes} minutes, so new jobs are not arriving. " \
    "Radar is restarting it. If this keeps happening, restart bin/dev."
  end

  # Enqueue a tick ourselves when the scheduler has clearly stopped. Cheap, safe
  # to call often, and does nothing at all while the scheduler is healthy.
  REVIVED_AT = "poll_revived_at".freeze

  def revive!
    return false unless stalled?

    last = Setting.get(REVIVED_AT)
    return false if last.present? && Time.zone.parse(last) > REVIVE_EVERY.ago

    Setting.set(REVIVED_AT, Time.current.iso8601)
    PollTickJob.perform_later
    Rails.logger.warn("[PollHealth] no tick for #{stalled_for.to_i}s, enqueued one directly")
    true
  rescue StandardError => e
    Rails.logger.warn("[PollHealth] revive failed: #{e.message}")
    false
  end
end
