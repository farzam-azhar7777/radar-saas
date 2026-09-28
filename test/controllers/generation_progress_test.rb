require "test_helper"

# The complaint this covers: pressing Rewrite left the old proposal on screen
# with nothing to distinguish it from a finished one, so there was no way to
# tell a running rewrite from a stalled one.
class GenerationProgressTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @search = SavedSearch.create!(name: "Rails", terms: [ "ruby on rails" ], threshold: 70, hot_threshold: 80)
    @posting = JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails dev",
                                  status: "matched", score: 82, saved_search: @search)
  end

  test "rewriting stamps the clock, so the page can show it running" do
    @posting.proposals.create!(version: 1, body: "v1", generated_at: 1.hour.ago)

    assert_not @posting.generating?, "nothing is running yet"

    post regenerate_job_posting_path(@posting), params: { feedback: "Lead with PadStats." }

    assert @posting.reload.generating?, "a rewrite must be visible as a rewrite"
    assert_enqueued_with(job: GenerateProposalJob)
  end

  test "a different template also counts as a running generation" do
    @posting.proposals.create!(version: 1, body: "v1", generated_at: 1.hour.ago)
    patch template_job_posting_path(@posting), params: { template_name: "personalised-skills-for-job" }
    assert @posting.reload.generating?
  end

  test "the page shows elapsed progress while a rewrite runs" do
    @posting.proposals.create!(version: 1, body: "the first draft", generated_at: 1.hour.ago)
    @posting.update!(generation_queued_at: 20.seconds.ago)

    get job_posting_path(@posting)

    assert_response :success
    assert_select "[data-controller~=?]", "generation", 1, "the live timer must be mounted"
    assert_match "Rewriting version 1", response.body
    assert_match "the first draft", response.body, "the old version stays copyable while the rewrite runs"
  end

  test "a first write shows progress with no proposal to fall back on" do
    @posting.update!(generation_queued_at: 5.seconds.ago)
    get job_posting_path(@posting)

    assert_response :success
    assert_select "[data-controller~=?]", "generation", 1
    assert_match "Writing your proposal", response.body
  end

  test "an idle posting mounts no timer and offers the button" do
    get job_posting_path(@posting)

    assert_response :success
    assert_select "[data-controller~=?]", "generation", 0
    assert_match "Write the proposal", response.body
  end

  test "a finished proposal mounts no timer" do
    @posting.update!(generation_queued_at: 3.minutes.ago)
    @posting.proposals.create!(version: 1, body: "done", generated_at: Time.current)

    get job_posting_path(@posting)

    assert_select "[data-controller~=?]", "generation", 0
    assert_match "done", response.body
  end

  # A long post used to push the client out of sight; it now comes first.
  test "the client leads the page, above the post" do
    @posting.update!(client_payment_verified: true, client_total_spent: 200, client_total_hires: 2, client_total_posted_jobs: 2)
    get job_posting_path(@posting)

    assert_select "section#client", 1
    body = response.body
    assert_operator body.index('id="client"'), :<, body.index(">The post<"), "the client must render before the post"
  end
end
