# Rewriting one part of a proposal.
#
# The whole-proposal rewrite in JobPostingsController stays exactly as it was.
# This is the cheaper path for "the opening is weak" rather than "start again".
class ProposalSectionsController < ApplicationController
  before_action :set_section

  def rewrite
    note = params[:feedback].to_s.strip
    return redirect_to @posting, alert: "Say what to change about that part first." if note.blank?

    # Two rewrites in flight would each build a version from the same parent and
    # one would silently win. One at a time, and the UI says so.
    if @posting.generating? || @proposal.rewriting_part?
      return redirect_to @posting, alert: "Something is already being written. Wait for it to land."
    end

    remember(note) if params[:scope] == "remember"

    @section.update!(rewrite_queued_at: Time.current, rewrite_feedback: note)
    RewriteSectionJob.perform_later(@section, feedback: note)
    BroadcastPosting.call(@posting)

    redirect_to @posting, notice: notice_for(note)
  end

  private

  # Same two-way choice as the whole-proposal box: fix this one, or teach it.
  def remember(note)
    feedback = Feedback.create!(
      job_posting: @posting, proposal: @proposal, saved_search: @posting.saved_search,
      body: "About the #{@section.display_label.inspect} part: #{note}", remembered: true
    )
    DistillLessonJob.perform_later(feedback)
  end

  def notice_for(note)
    base = "Rewriting #{@section.display_label.inspect}. Everything else stays."
    params[:scope] == "remember" ? "#{base} Remembering that for future proposals." : base
  end

  def set_section
    @section = ProposalSection.find(params[:id])
    @proposal = @section.proposal
    @posting = @proposal.job_posting
  end
end
