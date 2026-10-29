require "test_helper"

class NotInterestedTest < ActionDispatch::IntegrationTest
  setup do
    search = SavedSearch.create!(name: "Rails", terms: [ "ruby on rails" ], threshold: 70, hot_threshold: 80)
    @posting = JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails dev", status: "matched", score: 82,
                                  saved_search: search, detail_fetched_at: Time.current)
  end

  test "the button is there before any proposal is written" do
    get job_posting_path(@posting)
    assert_select "form[action=?] button", dismiss_job_posting_path(@posting), text: "Not interested"
  end

  test "the button is there while the proposal is being written" do
    @posting.update!(generation_queued_at: 10.seconds.ago)
    get job_posting_path(@posting)
    assert_select "form[action=?] button", dismiss_job_posting_path(@posting), text: "Not interested"
  end

  test "the button is there once the proposal is written, once only" do
    @posting.proposals.create!(version: 1, body: "v1", generated_at: Time.current)
    get job_posting_path(@posting)
    assert_select "form[action=?]", dismiss_job_posting_path(@posting), 1
  end

  test "a dismissed or applied job has no button" do
    %w[dismissed applied].each do |status|
      @posting.update!(status: status)
      get job_posting_path(@posting)
      assert_select "form[action=?]", dismiss_job_posting_path(@posting), 0
    end
  end

  test "a job dismissed before its write starts is not written" do
    @posting.update!(generation_queued_at: Time.current)
    post dismiss_job_posting_path(@posting)

    GenerateProposalJob.new.perform(@posting.reload)

    assert_equal 0, @posting.proposals.count, "nothing spent on a job he passed on"
    assert_equal "dismissed", @posting.reload.status
    assert_nil @posting.generation_queued_at
  end
end
