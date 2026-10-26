require "test_helper"

class AlertFreshnessTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class Source
    def search_all(*) = [ { "upwork_id" => "any" } ]
    def client_stats(*) = {}
  end

  setup do
    @search = SavedSearch.create!(name: "AI", terms: [ "ai agent" ], threshold: 70, hot_threshold: 80,
                                  auto_generate: true, active: true)
  end

  def job(published_at:, score: 90, **attrs)
    JobPosting.create!({ upwork_id: SecureRandom.hex(6), title: "AI engineer", status: "matched", score: score,
                         saved_search: @search, published_at: published_at }.merge(attrs))
  end

  test "a job counts as new only when it was posted within the last day" do
    assert job(published_at: 3.hours.ago).fresh?
    assert_not job(published_at: 14.days.ago).fresh?
    assert job(published_at: nil).fresh?, "with no posting time, when Radar found it stands in"
  end

  test "the digest never counts a job posted weeks ago" do
    fresh = job(published_at: 2.hours.ago, score: 72)
    job(published_at: 14.days.ago, score: 72)
    assert_equal [ fresh.id ], JobPosting.awaiting_digest.pluck(:id)
  end

  test "the alert feed announces only new strong matches, with their age and both actions" do
    fresh = job(published_at: 3.hours.ago)
    job(published_at: 14.days.ago)

    get alerts_path(format: :json)
    hot = response.parsed_body["hot"]

    assert_equal [ fresh.id ], hot.map { |h| h["id"] }
    assert_equal "Posted about 3 hours ago", hot.first["posted"]
    assert_match %r{/alerts/#{fresh.id}/write\?token=}, hot.first["write_url"]
    assert_match %r{/alerts/#{fresh.id}/dismiss\?token=}, hot.first["dismiss_url"]
  end

  test "Write from the alert starts the proposal once" do
    posting = job(published_at: 1.hour.ago)
    token = AlertActionsController.token_for(posting, "write")

    assert_enqueued_with(job: GenerateProposalJob) { post alert_write_path(posting, token: token) }
    assert_response :success
    assert posting.reload.generating?

    assert_no_enqueued_jobs(only: GenerateProposalJob) { post alert_write_path(posting, token: token) }
    assert_equal "Already written or being written.", response.parsed_body["message"]
  end

  test "Not interested from the alert dismisses the job" do
    posting = job(published_at: 1.hour.ago)
    post alert_dismiss_path(posting, token: AlertActionsController.token_for(posting, "dismiss"))

    assert_response :success
    assert_equal "dismissed", posting.reload.status
  end

  test "an alert action needs its own signed token" do
    posting = job(published_at: 1.hour.ago)
    other = job(published_at: 1.hour.ago)

    post alert_write_path(posting)
    assert_response :forbidden
    post alert_write_path(posting, token: AlertActionsController.token_for(posting, "dismiss"))
    assert_response :forbidden
    post alert_dismiss_path(posting, token: AlertActionsController.token_for(other, "dismiss"))
    assert_response :forbidden
    assert_equal "matched", posting.reload.status
  end

  test "a poll neither writes nor announces a strong match posted weeks ago" do
    fresh = job(published_at: 1.hour.ago)
    stale = job(published_at: 14.days.ago)
    source = Source.new
    original_source = JobSource.method(:current)
    original_ingest = IngestPostings.method(:call)
    JobSource.define_singleton_method(:current) { source }
    IngestPostings.define_singleton_method(:call) { |*, **| [ fresh, stale ] }

    PollAllSearchesJob.new.perform(all: true)

    written = enqueued_jobs.select { |j| j["job_class"] == "GenerateProposalJob" }
    assert_equal 1, written.size
    assert_match fresh.to_global_id.to_s, written.first["arguments"].to_s
    assert_nil stale.reload.notified_at
  ensure
    JobSource.define_singleton_method(:current, original_source)
    IngestPostings.define_singleton_method(:call, original_ingest)
  end
end
