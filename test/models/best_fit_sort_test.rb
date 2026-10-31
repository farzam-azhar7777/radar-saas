require "test_helper"

class BestFitSortTest < ActiveSupport::TestCase
  setup do
    @ai = SavedSearch.create!(name: "AI", terms: [ "ai" ], threshold: 70, hot_threshold: 80)
    @rails = SavedSearch.create!(name: "Rails", terms: [ "rails" ], threshold: 70, hot_threshold: 90)
  end

  def job(name, score:, hours_ago:, search: @ai)
    JobPosting.create!(upwork_id: name, title: name, status: "matched", score: score, saved_search: search,
                       published_at: hours_ago.hours.ago)
  end

  test "strong jobs come first, newest first, then the rest by fit" do
    job("strong-old", score: 95, hours_ago: 10)
    job("strong-new", score: 81, hours_ago: 1)
    job("strong-mid", score: 92, hours_ago: 5, search: @rails)
    job("fit-high-rails", score: 88, hours_ago: 2, search: @rails)
    job("fit-low", score: 72, hours_ago: 0.5)
    job("fit-mid", score: 75, hours_ago: 3)

    assert_equal %w[strong-new strong-mid strong-old fit-high-rails fit-mid fit-low],
                 JobPosting.sorted_by("fit").pluck(:upwork_id)
    assert JobPosting.find_by(upwork_id: "strong-new").hot?
    assert_not JobPosting.find_by(upwork_id: "fit-high-rails").hot?, "88 is under Rails' 90 alert line"
  end

  test "a job with no search is never counted as strong" do
    JobPosting.create!(upwork_id: "orphan", title: "x", status: "matched", score: 99, published_at: 1.hour.ago)
    job("strong", score: 85, hours_ago: 9)

    assert_equal %w[strong orphan], JobPosting.sorted_by("fit").pluck(:upwork_id)
  end
end
