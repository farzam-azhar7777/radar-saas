class JobPostingsController < ApplicationController
  before_action :set_posting, except: %i[index filtered applied]

  def index
    @sort = params[:sort].presence || "newest"
    @query = params[:q].to_s.strip
    @postings = JobPosting.where(status: %w[matched generation_failed])
                          .includes(:saved_search, :proposals)
                          .matching(@query)
                          .sorted_by(@sort)
    @postings = @postings.where(saved_search_id: params[:search]) if params[:search].present?
    @searches = SavedSearch.ordered
  end

  def filtered
    @sort = params[:sort].presence || "fit"
    @query = params[:q].to_s.strip
    @postings = JobPosting.where(status: "ignored")
                          .includes(:saved_search)
                          .matching(@query)
                          .sorted_by(@sort)
                          .limit(200)
    @postings = @postings.where(saved_search_id: params[:search]) if params[:search].present?
    @searches = SavedSearch.ordered
  end

  def applied
    @postings = JobPosting.applied.includes(:proposals, :saved_search)
    # One application counts once. Grouping proposals would count every
    # regeneration as a separate send and inflate the win rate.
    @by_archetype = @postings
      .filter_map { |p| [ p.latest_proposal&.archetype, p ] if p.latest_proposal&.archetype.present? }
      .group_by(&:first)
      .transform_values { |pairs|
        postings = pairs.map(&:last)
        { sent: postings.size,
          replied: postings.count { |x| x.outcome.present? && x.outcome != "no_reply" },
          won: postings.count(&:won?) }
      }
  end

  def show
    @proposal = @posting.latest_proposal
    @versions = @posting.proposals
    @templates = CareerData.instance.templates
    @archetype = ProposalArchetype.new(@posting)
    @lessons = Lesson.for(saved_search: @posting.saved_search, archetype: @archetype.label)
  end

  def refresh
    result = RefreshPosting.call(@posting)
    redirect_to @posting, notice: result.message
  end

  def generate
    queue_generation
    redirect_to @posting, notice: "Writing. This page shows it running."
  end

  # Feedback comes in two kinds and they were being treated as one. "Cut the
  # Loom paragraph" is about this client; "stop opening with my job title" is
  # about every proposal. Turning the first into a durable rule quietly changes
  # everything he writes from then on, so it has to be chosen, not assumed.
  def regenerate
    note = params[:feedback].presence
    remember = params[:scope] == "remember"

    if note
      feedback = Feedback.create!(
        job_posting: @posting,
        proposal: @posting.latest_proposal,
        saved_search: @posting.saved_search,
        body: note,
        remembered: remember
      )
      DistillLessonJob.perform_later(feedback) if remember
    end

    queue_generation(feedback: note)
    redirect_to @posting, notice: regenerate_notice(note, remember)
  end

  def template
    latest = @posting.latest_proposal
    latest&.update(template_name: params[:template_name])
    queue_generation(feedback: "Rewrite using the #{params[:template_name]} template.")
    redirect_to @posting, notice: "Rewriting with #{params[:template_name]}."
  end

  def dismiss
    @posting.update!(status: "dismissed")
    redirect_to root_path, notice: "Dismissed."
  end

  # From the Filtered out tab: "this was actually a match".
  def promote
    @posting.update!(status: "matched")
    queue_generation
    redirect_to @posting, notice: "Promoted. Writing a proposal now."
  end

  def restore
    @posting.update!(status: "matched")
    redirect_to @posting, notice: "Back in the inbox."
  end

  def outcome
    @posting.update!(outcome: params[:outcome], outcome_at: Time.current)
    redirect_back fallback_location: applied_path,
                  notice: "Noted: #{@posting.outcome_label.downcase}."
  end

  def mark_applied
    @posting.update!(
      status: "applied",
      applied_at: Time.current,
      rate_proposed: params[:rate_proposed].presence
    )
    path = ApplicationArchiver.call(@posting)
    redirect_to applied_path,
                notice: path ? "Marked applied. Archived to #{path.basename}." : "Marked applied."
  end

  private

  # Stamping the clock is what makes the UI able to say "running" at all. A
  # rewrite that only enqueued the job left the old proposal on screen with
  # nothing to distinguish it from a finished one.
  def regenerate_notice(note, remember)
    return "Rewriting." if note.blank?

    remember ? "Rewriting, and remembering that for future proposals." : "Rewriting this one. The note is not kept."
  end

  def queue_generation(feedback: nil)
    @posting.update_column(:generation_queued_at, Time.current)
    GenerateProposalJob.perform_later(@posting, feedback: feedback, force: true)
    BroadcastPosting.call(@posting)
  end

  def set_posting
    @posting = JobPosting.find(params[:id])
  end
end
