require "test_helper"

# "Sometimes, I want to rewrite with feedback to just this proposal only."
# Every note used to become a durable rule, so a one-off remark about one
# client quietly changed every proposal written afterwards.
class FeedbackScopeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @search = SavedSearch.create!(name: "Rails", terms: [ "ruby on rails" ], threshold: 70, hot_threshold: 80)
    @posting = JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails dev",
                                  status: "matched", score: 82, saved_search: @search)
    @posting.proposals.create!(version: 1, body: "v1", generated_at: 1.hour.ago)
  end

  def rewrite(scope, note: "Cut the Loom paragraph.")
    post regenerate_job_posting_path(@posting), params: { feedback: note, scope: scope }
  end

  test "rewriting this one does not create a lesson" do
    assert_no_enqueued_jobs(only: DistillLessonJob) { rewrite("once") }
    assert_enqueued_with(job: GenerateProposalJob)
  end

  test "rewriting this one still records the note, marked as not remembered" do
    assert_difference "Feedback.count", 1 do
      rewrite("once")
    end
    feedback = Feedback.order(:id).last
    assert_equal "Cut the Loom paragraph.", feedback.body
    assert_not feedback.remembered, "the evidence trail must say what was actually done with it"
  end

  test "rewrite and remember distils a lesson" do
    assert_enqueued_with(job: DistillLessonJob) { rewrite("remember") }
    assert Feedback.order(:id).last.remembered
  end

  test "the note reaches the rewrite either way" do
    %w[once remember].each do |scope|
      clear_enqueued_jobs
      rewrite(scope)
      job = enqueued_jobs.find { |j| j["job_class"] == "GenerateProposalJob" }
      assert_includes job.to_s, "Cut the Loom paragraph", "scope=#{scope} must still steer the rewrite"
    end
  end

  test "each choice says plainly what it did" do
    rewrite("once")
    assert_match "not kept", flash[:notice]

    rewrite("remember")
    assert_match "remembering", flash[:notice]
  end

  test "an empty note rewrites without recording anything" do
    assert_no_difference "Feedback.count" do
      assert_no_enqueued_jobs(only: DistillLessonJob) { rewrite("remember", note: "") }
    end
  end

  # f.submit puts the submitted value in the visible label, so the two buttons
  # read "once" and "remember" on screen. They have to be button elements.
  test "the buttons are labelled for a human and still submit the scope" do
    get job_posting_path(@posting)

    # Scoped to the whole-proposal form: each part now carries its own pair of
    # scope buttons, so an unscoped match would hit several forms at once.
    assert_select "form[action=?]", regenerate_job_posting_path(@posting) do
      assert_select "button[name=scope][value=once]", text: "Rewrite all of it"
      assert_select "button[name=scope][value=remember]", text: "Rewrite and remember"
    end
    assert_select "input[type=submit][name=scope]", 0, "an input would show the raw value as its label"
  end

  # Anything that posts without the parameter must not silently start learning.
  test "a missing scope defaults to this-one-only" do
    assert_no_enqueued_jobs(only: DistillLessonJob) do
      post regenerate_job_posting_path(@posting), params: { feedback: "Shorter." }
    end
    assert_not Feedback.order(:id).last.remembered
  end
end
