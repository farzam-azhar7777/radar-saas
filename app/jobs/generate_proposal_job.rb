class GenerateProposalJob < ApplicationJob
  queue_as :generation

  discard_on ActiveJob::DeserializationError

  # Anything that kills the job without reaching its own rescue still has to
  # leave the posting truthful rather than stuck showing "writing".
  after_discard do |job, _error|
    posting = job.arguments.first
    posting.update_columns(generation_queued_at: nil) if posting.is_a?(JobPosting) && posting.proposals.none?
  rescue StandardError
    nil
  end

  def perform(job_posting, feedback: nil, force: false)
    fetch_detail(job_posting)

    # The detail fetch is the first moment the client's location list exists,
    # and it happens before any money is spent. Stop here rather than writing a
    # proposal for a job that asks for a country Farzam is not in.
    return skip_for_location(job_posting) if !force && job_posting.location_mismatch?

    previous = job_posting.latest_proposal

    result = ProposalGenerator.call(
      job_posting,
      feedback: feedback,
      previous: previous&.body,
      template_name: previous&.template_name
    )

    proposal = job_posting.proposals.create!(
      version: (previous&.version || 0) + 1,
      body: result.body,
      feedback: feedback,
      template_name: previous&.template_name || job_posting.saved_search&.template_name,
      generated_at: Time.current,
      duration_ms: result.duration_ms,
      claude_meta: result.meta,
      archetype: result.archetype,
      checks: result.checks,
      attempts: result.attempts
    )

    # The editable view of the same text. Derived from the body when the writer
    # ignored the markers, so no proposal is ever un-editable part by part.
    proposal.build_sections_from(
      result.sections.presence || ProposalSectioner.call(result.body, posting: job_posting)
    )

    job_posting.status = "matched" if job_posting.status == "generation_failed"
    job_posting.generation_queued_at = nil
    job_posting.generation_error = nil
    job_posting.save!
    broadcast(job_posting, proposal)
    announce(job_posting, proposal)
  rescue ProposalGenerator::GenerationError => e
    Rails.logger.error("[GenerateProposalJob] posting #{job_posting.id}: #{e.message}")
    job_posting.update!(status: "generation_failed", generation_queued_at: nil,
                        generation_error: e.message.to_s.first(1000))
    broadcast(job_posting, nil)
  end

  private

  # Not a failure: nothing broke, and Farzam may still want to bid. Leave the
  # posting where it is, say why nothing was written, and leave the button.
  def skip_for_location(posting)
    posting.update!(generation_queued_at: nil,
                    generation_error: "Not written: the client restricted this to #{posting.location_label}. " \
                                      "Write one anyway if you want to bid.")
    Rails.logger.info("[GenerateProposalJob] posting #{posting.id} skipped, restricted to #{posting.location_label}")
    BroadcastPosting.call(posting)
    nil
  end

  # Screening questions live on a separate detail query, so we pay for it only
  # when we are actually about to write something.
  def fetch_detail(posting)
    return if posting.detail_fetched_at.present?

    detail = JobSource.current.detail(posting.upwork_id)
    return if detail.blank?

    posting.update!(detail.slice("cover_letter_required", "screening_questions",
                                 "preferred_locations", "detail_fetched_at")
                          .merge(detail["contract_type"].present? ? { "contract_type" => detail["contract_type"] } : {}))
  rescue StandardError => e
    Rails.logger.warn("[GenerateProposalJob] detail fetch failed for #{posting.id}: #{e.message}")
  end

  # The browser tab announces it from the alerts feed. This is the native Mac
  # path, off unless he turned it on, same as for a new job.
  def announce(posting, proposal)
    Notifier.notify(title: "Proposal ready", message: "#{posting.title.truncate(60)} · #{proposal.readiness}",
                    url: Rails.application.routes.url_helpers.job_posting_url(posting, **Radar.url_options))
  end

  # Live-update whichever screen is open, so the inbox fills in as proposals
  # land rather than needing a refresh.
  def broadcast(posting, _proposal)
    BroadcastPosting.call(posting)
  end
end
