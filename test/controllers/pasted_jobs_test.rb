require "test_helper"

class PastedJobsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  POST = "Build an AI voice agent for our call center\n\nWe need someone to wire Twilio to an LLM agent, " \
         "with RAG over our help docs and a Rails admin. Tell us about a similar project.".freeze

  setup do
    @ai = SavedSearch.create!(name: "AI", terms: [ "ai agent", "rag", "llm" ], threshold: 70, hot_threshold: 80)
    @rails = SavedSearch.create!(name: "Rails", terms: [ "rails" ], threshold: 70, hot_threshold: 80)
  end

  def paste(**fields) = post(pasted_jobs_path, params: { pasted_job: { post: POST }.merge(fields) })

  def pasted = JobPosting.pasted.first

  test "the menu has its own page, and the form asks for the post first" do
    get pasted_jobs_path
    assert_select "nav a[href=?]", pasted_jobs_path, text: /Pasted jobs/
    assert_select "a[href=?]", new_pasted_job_path, text: /Paste a job/

    get new_pasted_job_path
    assert_select "textarea[name='pasted_job[post]'][required]"
    assert_select "textarea[name='pasted_job[questions]']"
    assert_select "select[name='pasted_job[saved_search_id]'] option", text: "Pick for me"
  end

  test "pasting only the post writes a proposal for it, the same way as any job" do
    assert_enqueued_with(job: GenerateProposalJob) { paste }

    assert_redirected_to job_posting_path(pasted)
    assert_equal "Build an AI voice agent for our call center", pasted.title
    assert_match "Twilio", pasted.description
    assert pasted.upwork_id.start_with?("pasted-")
    assert_equal [ "matched", @ai ], [ pasted.status, pasted.saved_search ]
    assert pasted.generating?
    assert pasted.score.positive?
    assert pasted.detail_fetched_at, "with no link there is nothing to fetch, so the writer is not held up"
  end

  test "questions, budget, bids, title and a chosen search are all used" do
    paste(title: "Voice agent", questions: "Describe a similar project.\n\n  What is your availability?  \n",
          budget: "hourly", budget_min: "30", budget_max: "60", bids: "12", saved_search_id: @rails.id)

    assert_equal "Voice agent", pasted.title
    assert_equal [ "Describe a similar project.", "What is your availability?" ], pasted.screening_questions_list
    assert_equal "$30-60/hr", pasted.budget_label
    assert_equal [ 12, @rails ], [ pasted.total_applicants, pasted.saved_search ]

    paste(budget: "fixed", budget_min: "1500")
    assert_equal "$1500 fixed", JobPosting.pasted.first.budget_label
  end

  test "a pasted job stays out of the inbox, Passed over, alerts and the digest, and lists under Pasted jobs" do
    paste
    pasted.update!(score: 95, generation_queued_at: nil, notified_at: nil)

    get root_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(pasted)}", 0
    assert_empty JobPosting.inbox
    assert_empty JobPosting.awaiting_digest
    get alerts_path(format: :json)
    assert_empty response.parsed_body["hot"]

    get pasted_jobs_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(pasted)}", text: /Build an AI voice agent/
  end

  test "its job page says it was pasted, leads back to Pasted jobs, and drops what needs Upwork" do
    paste
    get job_posting_path(pasted)

    assert_select ".chip", "Pasted"
    assert_select "a[href=?]", pasted_jobs_path, text: /Pasted jobs/
    assert_select "button", text: /Refresh/, count: 0
    assert_select "#client", 0
  end

  test "the writer is not told guesses about a client or competition it was never given" do
    paste
    signals = ProposalArchetype.call(pasted)[:signals]
    assert_not signals.any? { |s| s.match?(/payment|hires|spend|proposals? already/) }, signals.inspect
    assert_nil pasted.applicants_per_hour

    paste(bids: "12")
    assert_includes ProposalArchetype.call(JobPosting.pasted.first)[:signals], "12 proposals already submitted"
  end

  test "on a pasted job's page the menu marks Pasted jobs, not Inbox" do
    paste
    get job_posting_path(pasted)
    assert_select "nav a[aria-current=page]", text: /Pasted jobs/
    assert_select "nav a[aria-current=page]", text: /Inbox/, count: 0
  end

  test "a post too short to write from is refused with the reason" do
    assert_no_difference("JobPosting.count") { paste(post: "Need a dev") }
    assert_response :unprocessable_entity
    assert_match "needs the job description", response.body
  end

  test "a link to a job Radar already has opens that job and writes for it, with no copy" do
    passed_over = JobPosting.create!(upwork_id: "2117183674717185074", title: "Voice agent", status: "ignored", score: 40, saved_search: @ai)

    assert_no_difference("JobPosting.count") do
      assert_enqueued_with(job: GenerateProposalJob) { paste(link: "https://www.upwork.com/jobs/~022117183674717185074?referrer=x") }
    end
    assert_redirected_to job_posting_path(passed_over)
    assert_equal "Radar already had this job. Writing its proposal now.", flash[:notice]
    assert_equal "matched", passed_over.reload.status
  end

  class Source
    def client_stats(*) = { client_total_posted_jobs: 10, client_jobs_with_hires: 7 }
  end

  test "a link to a new job keeps it on Upwork: its id, its address and the client's hiring record" do
    original = JobSource.method(:current)
    source = Source.new
    JobSource.define_singleton_method(:current) { source }

    paste(link: "https://www.upwork.com/jobs/Voice-agent_~021999888777666555444/")

    assert_equal [ "1999888777666555444", "https://www.upwork.com/jobs/~021999888777666555444" ], [ pasted.upwork_id, pasted.job_url ]
    assert pasted.on_upwork?
    assert_equal 70, pasted.client_hire_rate
    assert_nil pasted.detail_fetched_at, "with no questions pasted, the writer reads them from Upwork"
  ensure
    JobSource.define_singleton_method(:current, original)
  end

  test "a link that is not an Upwork job is refused" do
    paste(link: "https://example.com/job/1")
    assert_response :unprocessable_entity
    assert_match "Link is not an Upwork job link", response.body
  end

  test "dismissing a pasted job returns to Pasted jobs" do
    paste
    post dismiss_job_posting_path(pasted)
    assert_redirected_to pasted_jobs_path
  end
end
