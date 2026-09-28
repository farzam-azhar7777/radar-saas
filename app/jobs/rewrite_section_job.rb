# Applies a one-part rewrite as a new proposal version.
#
# A new version rather than an edit in place, for the same reason a full
# regeneration makes one: he can read what changed and go back. The other parts
# are copied across untouched, so the version list shows exactly one part
# moving, which is the whole reason to rewrite a part rather than the proposal.
class RewriteSectionJob < ApplicationJob
  queue_as :generation

  discard_on ActiveJob::DeserializationError

  # A part left spinning because the process died is worse than a visible
  # failure: there is no button to press and no error to read.
  after_discard do |job, _error|
    section = job.arguments.first
    section.update_columns(rewrite_queued_at: nil) if section.is_a?(ProposalSection)
  rescue StandardError
    nil
  end

  def perform(section, feedback:)
    proposal = section.proposal
    posting = proposal.job_posting

    result = SectionRewriter.call(section, feedback: feedback)
    fresh = build_version(proposal, section, result, feedback)

    section.update_columns(rewrite_queued_at: nil)
    posting.update_columns(generation_error: nil) if posting.generation_error.present?
    BroadcastPosting.call(posting)
    fresh
  rescue SectionRewriter::RewriteError => e
    Rails.logger.error("[RewriteSectionJob] section #{section.id}: #{e.message}")
    section.update_columns(rewrite_queued_at: nil)
    section.proposal.job_posting.update!(
      generation_error: "Rewriting #{section.display_label.inspect} failed: #{e.message.to_s.first(400)}"
    )
    BroadcastPosting.call(section.proposal.job_posting)
  end

  private

  def build_version(proposal, section, result, feedback)
    posting = proposal.job_posting

    fresh = nil
    ActiveRecord::Base.transaction do
      fresh = posting.proposals.create!(
        version: (posting.proposals.maximum(:version) || 0) + 1,
        body: "",
        feedback: feedback,
        template_name: proposal.template_name,
        archetype: proposal.archetype,
        generated_at: Time.current,
        duration_ms: result.duration_ms,
        attempts: 1,
        claude_meta: result.meta.to_h.merge("rewritten_section" => section.display_label)
      )

      rows = proposal.sections.map.with_index do |s, i|
        { proposal_id: fresh.id, position: i, label: s.label, role: s.role,
          # A dash has one right answer, and it is fixed here rather than
          # failing the whole proposal over one rewritten part.
          body: s.id == section.id ? ProposalAutofix.plain_dashes(result.body.to_s) : s.body,
          rewrite_feedback: s.id == section.id ? feedback : s.rewrite_feedback,
          rewrite_duration_ms: s.id == section.id ? result.duration_ms : s.rewrite_duration_ms,
          rewrite_meta: s.id == section.id ? result.meta.to_h : (s.rewrite_meta || {}),
          created_at: Time.current, updated_at: Time.current }
      end
      ProposalSection.insert_all!(rows)

      # Assembled from the parts, then re-checked whole. A part that reads well
      # on its own can still push the letter over budget or over Upwork's
      # character limit, and only the assembled text can show that.
      fresh.sections.reset
      body = fresh.assembled
      fresh.update!(body: body, checks: ProposalCheck.call(body, archetype: ProposalArchetype.call(posting), posting: posting))
    end
    fresh
  end
end
