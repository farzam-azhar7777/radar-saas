module Setup
  # The last step, and the one that decides setup is finished: a real job,
  # a real proposal, and the person saying they would send it.
  class FirstProposalsController < BaseController
    POSTING = "setup.first_posting_id".freeze

    # One real poll, now, rather than waiting for the scheduler's next tick.
    def check
      Setting.clear(POSTING)
      Setting.set("setup.first_check_at", Time.current.iso8601)
      PollAllSearchesJob.perform_later(all: true)
      go_to("first_proposal", notice: "Checking Upwork with your searches. Matches appear here in a moment.")
    end

    def pick
      posting = JobPosting.find(params[:id])
      start(posting)
    end

    # For when nothing good is open right now: any job post, pasted.
    def paste
      title = params[:title].to_s.strip
      description = params[:description].to_s.strip
      if title.blank? || description.length < 80
        return go_to("first_proposal", alert: "Paste the job's title and its full description (at least a few sentences).")
      end

      posting = JobPosting.create!(
        upwork_id: "pasted-#{SecureRandom.hex(6)}", title: title, description: description,
        status: "matched", published_at: Time.current, detail_fetched_at: Time.current,
        screening_questions: params[:questions].to_s.lines.map(&:strip).reject(&:blank?),
        saved_search: SavedSearch.active.ordered.first
      )
      start(posting)
    end

    def verdict
      posting = JobPosting.find_by(id: Setting.get(POSTING))
      return go_to("first_proposal") unless posting&.proposal_ready?

      if params[:send] == "yes"
        Onboarding.stamp!("first_proposal")
        Onboarding.complete!
        redirect_to job_posting_path(posting), notice: "Setup is done. Radar is watching Upwork for you."
      else
        note = params[:feedback].to_s.strip
        return go_to("first_proposal", alert: "Say what is wrong with it, so the rewrite can fix it.") if note.blank?

        feedback = Feedback.create!(job_posting: posting, proposal: posting.latest_proposal,
                                    saved_search: posting.saved_search, body: note, remembered: params[:remember] == "1")
        DistillLessonJob.perform_later(feedback) if feedback.remembered?
        posting.update_column(:generation_queued_at, Time.current)
        GenerateProposalJob.perform_later(posting, feedback: note, force: true)
        go_to("first_proposal", notice: "Rewriting it with your note.")
      end
    end

    private

    def start(posting)
      Setting.set(POSTING, posting.id)
      posting.update_columns(generation_queued_at: Time.current, status: "matched")
      GenerateProposalJob.perform_later(posting, force: true)
      go_to("first_proposal")
    end
  end
end
