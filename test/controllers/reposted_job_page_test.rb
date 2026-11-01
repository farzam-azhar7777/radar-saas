require "test_helper"

class RepostedJobPageTest < ActionDispatch::IntegrationTest
  setup do
    search = SavedSearch.create!(name: "AI", terms: [ "ai" ], threshold: 70, hot_threshold: 80)
    @first = JobPosting.create!(upwork_id: "first", title: "AI Architect trainer", status: "ignored", score: 75,
                                saved_search: search, published_at: Time.zone.local(2026, 10, 26, 9))
    @copy = JobPosting.create!(upwork_id: "copy", title: "AI Architect trainer", status: "matched", score: 75,
                               saved_search: search, published_at: 1.hour.ago, repost_of: @first, repost_count: 1)
  end

  test "the inbox row says how often the job was posted" do
    get root_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(@copy)} .chip", "Posted 2 times"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@first)}", 0
  end

  test "the job page warns and links to the first posting" do
    get job_posting_path(@copy)
    assert_select ".notice-warn", text: /Posted 2 times since Oct 26\. Sometimes a relist, sometimes a client who never hires/
    assert_select ".notice-warn a[href=?]", job_posting_path(@first), text: "See the first posting"
  end

  test "a job posted once shows no warning" do
    get job_posting_path(@first)
    assert_select ".notice-warn", 0
  end
end
