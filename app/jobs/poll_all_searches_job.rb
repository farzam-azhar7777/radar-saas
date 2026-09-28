# One poll cycle: a single combined search across every active saved search,
# then triage.
#
#   hot + auto_generate   notify now, write the proposal now
#   hot                   notify now, wait for the person to ask
#   matched               inbox only, folded into the next digest
#   ignored               Filtered out, never notified
class PollAllSearchesJob < ApplicationJob
  queue_as :default

  # all: true queries every search now, as setup's first check does, rather
  # than only the ones due this cycle.
  def perform(all: false)
    all_searches = SavedSearch.active.ordered.to_a
    return if all_searches.empty?

    # Tier A carries the 5-minute promise, so it is queried every cycle. The
    # notify-only categories are checked every third cycle, which cuts the
    # daily call count by roughly half without affecting the jobs that matter.
    searches = all ? all_searches : due_searches(all_searches)
    return if searches.empty?

    unless ApiUsage.room_for?(2)
      Rails.logger.warn("[Poll] skipped, #{ApiUsage.used_today}/#{Radar.daily_request_cap} requests used today")
      return
    end

    rows = begin
      JobSource.current.search_all(searches)
    rescue Upwork::Error => e
      Rails.logger.error("[Poll] search failed, skipping this cycle: #{e.class}: #{e.message}")
      []
    end
    return if rows.empty?

    # Ingest against every search, so a job found by a Tier B query can still be
    # re-homed to Rails and treated as Tier A.
    matched = IngestPostings.call(rows, searches: all_searches)
    hot, quiet = matched.partition(&:hot?)

    generate(hot)
    notify_hot(hot)
    maybe_digest
    Rails.logger.info("[Poll] #{rows.size} seen, #{matched.size} matched, #{hot.size} hot")
  end

  private

  SECONDARY_EVERY = 3

  def due_searches(all_searches)
    cycle = Setting.get("poll_cycle", "0").to_i + 1
    Setting.set("poll_cycle", cycle)

    primary, secondary = all_searches.partition(&:auto_generate?)
    (cycle % SECONDARY_EVERY).zero? ? all_searches : primary.presence || all_searches
  end

  # This method spends money, so it enforces its own rules rather than trusting
  # the caller to have filtered correctly. Only searches the person marked as
  # auto-writing may ever produce a proposal without him asking.
  def generate(candidates)
    candidates = Array(candidates).select { |p| p.saved_search&.auto_generate? }
    return if candidates.empty?
    # Setup's first check finds jobs; the person picks which one to write.
    return Rails.logger.info("[Poll] setup not finished, #{candidates.size} hot left for the person to pick") unless Onboarding.complete?
    return Rails.logger.info("[Poll] auto-write off, #{candidates.size} hot left unwritten") unless Setting.auto_generate?

    room = [ Radar.daily_generation_cap - Proposal.where(created_at: Time.current.all_day).count, 0 ].max
    allowance = [ Radar.max_generations_per_poll, room ].min

    candidates.sort_by { |p| -p.score.to_i }.first(allowance).each do |posting|
      posting.update_column(:generation_queued_at, Time.current)
      GenerateProposalJob.perform_later(posting)
    end
  end

  def notify_hot(hot)
    return if hot.empty?

    top = hot.max_by { |p| p.score.to_i }
    writing = top.saved_search&.auto_generate? ? " Writing now." : ""
    message =
      if hot.one?
        "#{top.score} · #{top.title.truncate(60)}#{writing}"
      else
        "#{hot.size} strong matches. Top: #{top.title.truncate(45)} (#{top.score})#{writing}"
      end

    Notifier.notify(title: "Upwork Radar", message: message, url: url_for(top))
    JobPosting.where(id: hot.map(&:id)).update_all(notified_at: Time.current)
  end

  def maybe_digest
    waiting = JobPosting.awaiting_digest.to_a
    return if waiting.empty?

    oldest = waiting.filter_map(&:created_at).min
    return unless waiting.size >= Radar.digest_size ||
                  (oldest.present? && oldest < Radar.digest_after_hours.hours.ago)

    top = waiting.max_by { |p| p.score.to_i }
    Notifier.notify(
      title: "Upwork Radar",
      message: "#{waiting.size} jobs waiting. Best is #{top.score}, #{top.title.truncate(50)}",
      url: root_url
    )
    JobPosting.where(id: waiting.map(&:id)).update_all(notified_at: Time.current)
  end

  def root_url = Rails.application.routes.url_helpers.root_url(**Radar.url_options)
  def url_for(posting) = Rails.application.routes.url_helpers.job_posting_url(posting, **Radar.url_options)
end
