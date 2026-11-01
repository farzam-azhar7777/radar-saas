require "test_helper"

class ColourMeaningTest < ActionDispatch::IntegrationTest
  setup do
    @search = SavedSearch.create!(name: "AI", terms: [ "ai" ], threshold: 70, hot_threshold: 80)
  end

  test "a strong match is green in the inbox: its tag and its fit ring" do
    strong = JobPosting.create!(upwork_id: "strong", title: "AI engineer", status: "matched", score: 91,
                                saved_search: @search, published_at: 1.hour.ago)
    get root_path

    row = "##{ActionView::RecordIdentifier.dom_id(strong)}"
    assert_select "#{row} .chip.chip-good", "Strong"
    assert_select "#{row} .chip-signal", 0
    assert_select "#{row} .dial.dial-strong"
  end

  test "the fit ring turns green exactly when the job is tagged Strong, by its own search's alert line" do
    rails = SavedSearch.create!(name: "Rails", terms: [ "rails" ], threshold: 70, hot_threshold: 90)
    at_line = JobPosting.create!(upwork_id: "at-line", title: "AI", status: "matched", score: 82, saved_search: @search, published_at: 1.hour.ago)
    under_line = JobPosting.create!(upwork_id: "under", title: "Rails", status: "matched", score: 88, saved_search: rails, published_at: 1.hour.ago)
    get root_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(at_line)} .dial.dial-strong"
    assert_select "##{ActionView::RecordIdentifier.dom_id(under_line)} .dial-strong", 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(under_line)} .chip-good", 0
  end

  test "a search's alert line is a setting, not a warning" do
    get saved_searches_path
    assert_select "span.text-signal", { text: "80", count: 0 }
  end
end
