# Browser-notification feed. macOS silently swallows notifications from CLI
# tools that were never granted permission, and a CLI never gets the permission
# prompt. Chrome does, so the open tab is a second, self-healing alert path.
class AlertsController < ApplicationController
  # Ordered by arrival, not by score. This feed exists to announce what is NEW.
  # Ranking it by score meant a fresh hot job scoring below the standing top ten
  # never entered the feed at all, so it was never announced.
  LIMIT = 40
  WRITTEN_WINDOW = 1.day

  def index
    hot = JobPosting.inbox.includes(:saved_search)
                    .select(&:hot?)
                    .sort_by { |p| -(p.created_at || p.published_at || Time.at(0)).to_i }

    render json: {
      hot: hot.first(LIMIT).map { |p|
        { id: p.id, title: p.title, score: p.score, budget: p.budget_label,
          search: p.saved_search&.name, url: job_posting_path(p),
          ready: p.proposal_ready? }
      },
      # Every proposal a generation produced, auto-written or asked for. Not a
      # one-part rewrite: he pressed that button and is looking at the result.
      written: Proposal.where(created_at: WRITTEN_WINDOW.ago..).includes(:job_posting)
                       .order(created_at: :desc).limit(LIMIT).reject(&:part_rewrite?)
                       .map { |p|
                         { id: p.id, version: p.version, title: p.job_posting.title,
                           url: job_posting_path(p.job_posting), readiness: p.readiness, to_fix: p.to_fix.size }
                       },
      failed: JobPosting.where(status: "generation_failed")
                        .where(updated_at: GenerationHealth::WINDOW.ago..)
                        .order(updated_at: :desc).limit(LIMIT)
                        .map { |p| { id: p.id, title: p.title, url: job_posting_path(p) } },
      writer_blocked: GenerationHealth.blocked?,
      polling_stalled: PollHealth.stalled?,
      waiting: JobPosting.awaiting_digest.count,
      digest_size: Radar.digest_size,
      inbox_count: JobPosting.inbox.count
    }
  end
end
