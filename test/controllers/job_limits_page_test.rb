require "test_helper"

class JobLimitsPageTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @ai = SavedSearch.create!(name: "AI", terms: [ "ai agent" ], threshold: 70, hot_threshold: 80, auto_generate: true)
    @rails = SavedSearch.create!(name: "Rails", terms: [ "ruby on rails" ], threshold: 70, hot_threshold: 85)
  end

  def match(**attrs)
    JobPosting.create!({ upwork_id: SecureRandom.hex(6), title: "AI engineer", status: "matched", score: 90,
                         saved_search: @ai, published_at: 1.hour.ago }.merge(attrs))
  end

  test "one Limits panel sits above the searches, and no search has limits of its own" do
    get saved_searches_path

    assert_select "#limits h2", "Limits"
    assert_select "#limits form[action=?]", job_limits_path
    assert_select "#limits input[name='limits[hire_rate][min]']"
    assert_select "#limits", text: /None set/
    assert_select "[id^=search_][id*=limits]", 0
    assert_select "#bulk-form input[name*=limits]", 0
    assert_select "input[name='saved_search[min_hourly]']", 0
  end

  test "saving sets the limits for every search and shows them with what they would have done" do
    match(total_applicants: 40)
    match(total_applicants: 3)

    patch job_limits_path, params: { limits: { "bids" => { "min" => "", "max" => "20" } } }
    assert_redirected_to saved_searches_path
    assert_equal({ "bids" => { "max" => 20 } }, JobLimits.current.to_h)

    follow_redirect!
    assert_select "#limits li.chip", "Bids so far at most 20"
    assert_select "#limits", text: /1\s+of 2 matches from the last 7 days\s+would have been passed over/
    assert_select "#limits", text: /Mostly by bids so far \(1\)/
  end

  test "an impossible range is refused, with the editor left open on what was typed" do
    patch job_limits_path, params: { limits: { "bids" => { "min" => "30", "max" => "10" } } }

    assert_response :unprocessable_entity
    assert_match "bids so far min must be at or below its max", response.body
    assert_select "#limits-editor:not([hidden]) input[name='limits[bids][min]'][value='30']"
    assert_not JobLimits.current.any?
  end

  test "the preview counts what unsaved limits would pass over, and warns when it is a lot" do
    match(fixed_amount: 100)
    match(fixed_amount: 200)
    match(fixed_amount: 9000)

    get preview_job_limits_path, params: { limits: { "fixed_price" => { "min" => "5000" } } }

    assert_response :success
    assert_match(/2<\/span>\s*<span[^>]*>of 3 matches/, response.body)
    assert_match "That is 66% of your matches", response.body
    assert_not JobLimits.current.any?, "a preview saves nothing"
  end

  class Source
    def search_all(*) = [ { "upwork_id" => "any" } ]
    def client_stats(upwork_id) = upwork_id == "picky" ? { client_total_posted_jobs: 10, client_jobs_with_hires: 2 } : {}
  end

  test "a poll files jobs outside a limit under Passed over, before and after the hire rate is known" do
    JobLimits.new("bids" => { "max" => 20 }, "hire_rate" => { "min" => 50 }).save
    kept = match(upwork_id: "kept", total_applicants: 5)
    crowded = match(upwork_id: "crowded", total_applicants: 40, saved_search: @rails, score: 95)
    picky = match(upwork_id: "picky", total_applicants: 5)

    original_source = JobSource.method(:current)
    original_ingest = IngestPostings.method(:call)
    source = Source.new
    JobSource.define_singleton_method(:current) { source }
    IngestPostings.define_singleton_method(:call) { |*, **| [ kept, crowded, picky ] }

    PollAllSearchesJob.new.perform(all: true)

    assert_equal %w[matched ignored ignored], [ kept, crowded, picky ].map { |p| p.reload.status }
    assert_equal "Bids so far 40, over your 20 maximum", crowded.score_reasons.last["note"]
    assert_equal "Client hire rate 20%, under your 50% minimum", picky.score_reasons.last["note"]
    written = enqueued_jobs.select { |j| j["job_class"] == "GenerateProposalJob" }
    assert_equal 1, written.size
    assert_match kept.to_global_id.to_s, written.first["arguments"].to_s
  ensure
    JobSource.define_singleton_method(:current, original_source)
    IngestPostings.define_singleton_method(:call, original_ingest)
  end
end
