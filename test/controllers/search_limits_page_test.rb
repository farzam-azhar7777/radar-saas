require "test_helper"

class SearchLimitsPageTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @ai = SavedSearch.create!(name: "AI", terms: [ "ai agent" ], threshold: 70, hot_threshold: 80, auto_generate: true,
                              limits: { "bids" => { "max" => 20 } })
    @rails = SavedSearch.create!(name: "Rails", terms: [ "ruby on rails" ], threshold: 70, hot_threshold: 85)
  end

  test "each search shows its limits and can edit them, and the bulk panel can set them" do
    get saved_searches_path

    assert_select "p", text: /Limits:\s*Bids so far at most 20/
    assert_select "#search_#{@ai.id}_saved_search_limits_bids_max[value='20']"
    assert_select "#search_#{@rails.id}_saved_search_limits_hire_rate_min"
    assert_select "#bulk_limits_hire_rate_min[form]", 0
    assert_select "form#bulk-form #bulk_limits_hire_rate_min"
  end

  test "an inline edit sets and clears limits" do
    patch saved_search_path(@ai), params: { saved_search: { name: "AI", limits: {
      "hire_rate" => { "min" => "50", "max" => "" }, "bids" => { "min" => "", "max" => "" } } } }

    assert_redirected_to saved_searches_path
    assert_equal({ "hire_rate" => { "min" => 50 } }, @ai.reload.limits)
  end

  test "an impossible range is refused with a reason" do
    patch saved_search_path(@ai), params: { saved_search: { name: "AI", limits: { "bids" => { "min" => "30", "max" => "10" } } } }

    assert_response :unprocessable_entity
    assert_match "Bids so far min must be at or below its max", response.body
  end

  test "bulk sets only the limits filled in and keeps each search's others" do
    post bulk_saved_searches_path, params: { ids: [ @ai.id, @rails.id ],
                                             bulk: { active: "", limits: { "hire_rate" => { "min" => "60", "max" => "" } } } }

    assert_equal "Updated 2 searches.", flash[:notice]
    assert_equal({ "bids" => { "max" => 20 }, "hire_rate" => { "min" => 60 } }, @ai.reload.limits)
    assert_equal({ "hire_rate" => { "min" => 60 } }, @rails.reload.limits)
  end

  class Source
    def search_all(*) = [ { "upwork_id" => "any" } ]
    def client_stats(upwork_id) = upwork_id == "picky" ? { client_total_posted_jobs: 10, client_jobs_with_hires: 2 } : {}
  end

  test "a poll files jobs outside a limit under Filtered out, before and after the hire rate is known" do
    @ai.update!(limits: { "bids" => { "max" => 20 }, "hire_rate" => { "min" => 50 } })
    job = ->(id, **attrs) {
      JobPosting.create!({ upwork_id: id, title: "AI engineer", status: "matched", score: 90, saved_search: @ai,
                           published_at: 1.hour.ago }.merge(attrs))
    }
    kept = job.call("kept", total_applicants: 5)
    crowded = job.call("crowded", total_applicants: 40)
    picky = job.call("picky", total_applicants: 5)

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
    assert_nil crowded.notified_at
  ensure
    JobSource.define_singleton_method(:current, original_source)
    IngestPostings.define_singleton_method(:call, original_ingest)
  end
end
