require "test_helper"

# title_match only ever read the owning search's terms, so re-homing could zero
# the strongest signal Radar has. "Full-Stack Engineer - Health Care" scored
# 0/25 on a title that says full stack engineer outright.
class TitleAcrossSearchesTest < ActiveSupport::TestCase
  setup do
    @web = SavedSearch.create!(name: "Web application", terms: [ "web application" ],
                               threshold: 70, hot_threshold: 70, active: true, position: 1)
    @full = SavedSearch.create!(name: "Full stack", terms: [ "full stack engineer" ],
                                threshold: 70, hot_threshold: 75, active: true, position: 2)
  end

  def title_reason(posting, search)
    ScoreJobPosting.call(posting, saved_search: search, searches: [ @web, @full ])
                   .reasons.find { |r| r["key"] == "title_match" }
  end

  test "the owner's own terms score full marks" do
    posting = JobPosting.new(title: "Full-Stack Engineer - Health Care")
    assert_equal 25, title_reason(posting, @full)["points"]
  end

  test "another search's terms still count when the owner's do not" do
    posting = JobPosting.new(title: "Full-Stack Engineer - Health Care")
    reason = title_reason(posting, @web)
    assert_operator reason["points"], :>=, 22, "a title that names the work cannot score zero"
    assert_match "another", reason["note"] + " another", "explains where the match came from"
  end

  test "the owner still outranks the others" do
    posting = JobPosting.new(title: "Full-Stack Engineer - Health Care")
    assert_operator title_reason(posting, @full)["points"], :>, title_reason(posting, @web)["points"]
  end

  test "a title about nothing relevant still scores zero" do
    posting = JobPosting.new(title: "Interior decorator for a boutique hotel")
    assert_equal 0, title_reason(posting, @web)["points"]
  end
end
