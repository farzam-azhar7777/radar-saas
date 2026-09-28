# Runs every minute and decides whether a poll is actually due. Cadence lives
# here rather than in recurring.yml so the interval can be jittered and can
# differ between waking hours and the middle of the night. A metronome-exact
# call every 180.000 seconds is the most obvious bot signature there is.
class PollTickJob < ApplicationJob
  queue_as :default

  NEXT_POLL_AT = "next_poll_at".freeze
  LAST_TICK_AT = "last_tick_at".freeze

  def perform
    # Stamped first, and on every tick rather than every poll, so it measures
    # whether the scheduler is alive rather than whether Upwork was busy.
    Setting.set(LAST_TICK_AT, Time.current.iso8601)
    ReapStuckGenerationsJob.perform_now

    # Nothing is watched until setup is finished. A search saved halfway
    # through would otherwise start writing proposals before the person's
    # work and preferences are in, spending their allowance on weak drafts.
    return unless Onboarding.complete?
    # Paused by the person. Check now still works; only the automatic
    # checking stops.
    return unless Setting.auto_polling?

    due = Setting.get(NEXT_POLL_AT)
    return if due.present? && Time.zone.parse(due) > Time.current

    schedule_next
    PollAllSearchesJob.perform_now
  end

  private

  def schedule_next
    Setting.set(NEXT_POLL_AT, Radar.next_interval.seconds.from_now.iso8601)
  end
end
