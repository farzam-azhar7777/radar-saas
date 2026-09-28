class LessonsController < ApplicationController
  def index
    @lessons = Lesson.includes(:saved_search).order(active: :desc, created_at: :desc)
    @feedbacks = Feedback.includes(:job_posting, :saved_search).recent.limit(30)
    @searches = SavedSearch.ordered
  end

  # Feedback that is not about any one proposal. Until now the only way to
  # teach Radar anything was to rewrite a proposal, so a thought like "stop
  # using the word platform" had to be attached to a job it was not about, and
  # cost a full regeneration to say.
  def teach
    note = params[:body].to_s.strip
    return redirect_to lessons_path, alert: "Nothing to save." if note.blank?

    search = SavedSearch.find_by(id: params[:saved_search_id])
    feedback = Feedback.create!(body: note, saved_search: search, remembered: true)

    # Distilling costs money, so it is the thing you have to ask for. Anything
    # that posts without saying which it wants gets the free one.
    if params[:mode] == "distill"
      feedback.update!(outcome: Feedback::PENDING)
      DistillLessonJob.perform_later(feedback)
      redirect_to lessons_path, notice: "Noted. Radar is wording it as a rule, which takes a moment."
    else
      # Instant and free. He often knows the exact rule he wants, and paying
      # Claude to reword it only risks changing what it means.
      lesson = Lesson.create!(body: note, saved_search: search, source_feedback: note)
      feedback.update!(outcome: Feedback::LEARNED, lesson: lesson)
      redirect_to lessons_path, notice: "Saved. It applies from the next proposal on."
    end
  end

  # Overruling a skip. The distiller decides a note is already covered or too
  # one-off, and it is usually right, but it is not the one who has to live
  # with the proposals. This takes the note verbatim and makes it a rule.
  def keep
    feedback = Feedback.find(params[:id])
    return redirect_to lessons_path, alert: "That note is already a rule." if feedback.learned?

    lesson = Lesson.create!(body: feedback.body, saved_search: feedback.saved_search,
                            source_feedback: feedback.body)
    feedback.update!(outcome: Feedback::LEARNED, lesson: lesson, outcome_note: nil)
    redirect_to lessons_path, notice: "Kept it, in your words. It applies from the next proposal on."
  end

  def update
    lesson = Lesson.find(params[:id])
    if params[:toggle]
      lesson.update!(active: !lesson.active?)
      redirect_to lessons_path, notice: lesson.active? ? "Rule is on again." : "Rule is off."
    else
      lesson.update!(body: params[:lesson][:body])
      redirect_to lessons_path, notice: "Rule updated."
    end
  end

  def destroy
    Lesson.find(params[:id]).destroy
    redirect_to lessons_path, notice: "Rule deleted."
  end
end
