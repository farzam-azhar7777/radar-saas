require "test_helper"

class PassedOverReasonsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @ai = SavedSearch.create!(name: "AI", terms: [ "ai" ], threshold: 70, hot_threshold: 90)
  end

  def passed(score, **attrs)
    JobPosting.create!({ upwork_id: SecureRandom.hex(6), title: "Job #{score}", status: "ignored", score: score, saved_search: @ai,
                         published_at: 1.hour.ago,
                         score_reasons: [ { "key" => "title_match", "points" => 0, "max" => 25, "note" => "Title is not about this kind of work" },
                                          { "key" => "budget", "points" => 8, "max" => 15, "note" => "Budget not stated" },
                                          { "key" => "recency", "points" => 12, "max" => 12, "note" => "Posted 4m ago" } ] }.merge(attrs))
  end

  test "each passed-over job says plainly why, and the ones that just missed stand out" do
    near = passed(67)
    far = passed(41)
    get filtered_path

    assert_select "p", text: "Scored 67, 3 under the AI search's inbox line of 70."
    assert_select "p", text: "Scored 41, 29 under the AI search's inbox line of 70."
    assert_select "li", text: /Title match 0 of 25: Title is not about this kind of work/
    assert_select "li", text: /Recency/, count: 0
    assert_select ".chip-warn", text: "Just missed", count: 1
    assert_select "a[href=?]", job_posting_path(far)
  end

  test "reposts and limits give their own reason" do
    passed(30, score_reasons: [ { "key" => "outside_limits", "points" => 0, "max" => 100, "note" => "Hourly rate under your $30 minimum" } ])
    get filtered_path
    assert_select "p", text: "Outside your job limits: Hourly rate under your $30 minimum"
  end

  test "moving a job back remembers why it was passed over" do
    job = passed(66)
    post promote_job_posting_path(job)
    job.reload
    assert_equal "matched", job.status
    assert job.moved_back_at
    assert_equal({ "kind" => "score", "score" => 66, "search_id" => @ai.id, "threshold" => 70, "gap" => 4 }, job.passed_over_for.except("headline"))
  end

  test "after three moves back from one search, Radar suggests lowering its line, and applying it moves the jobs that now clear" do
    [ 66, 64, 68 ].each { |s| post promote_job_posting_path(passed(s)) }
    waiting = passed(65)
    passed(50)
    get filtered_path
    assert_select ".notice", text: /Lower the AI search's inbox line from 70 to 64\?/
    assert_select ".notice", text: /You moved 3 of its passed-over jobs back.*1 from the last week would move there now/m

    post apply_passed_over_advice_path, params: { search_id: @ai.id, to: 64 }
    assert_equal 64, @ai.reload.threshold
    assert_equal "matched", waiting.reload.status
    assert_match "1 recent job that clear it moved to the inbox", flash[:notice]

    get filtered_path
    assert_select ".notice", text: /Lower the AI search/, count: 0
  end

  test "two moves are not a pattern yet, and Not now hides a suggestion" do
    [ 66, 64 ].each { |s| post promote_job_posting_path(passed(s)) }
    assert_empty PassedOverAdvice.suggestions

    post promote_job_posting_path(passed(62))
    key = PassedOverAdvice.suggestions.sole.key
    delete dismiss_passed_over_advice_path, params: { key: key }
    assert_empty PassedOverAdvice.suggestions
    assert_equal 70, @ai.reload.threshold
  end

  test "Not interested is on every inbox row and returns to the list" do
    job = JobPosting.create!(upwork_id: "inbox-1", title: "Voice agent", status: "matched", score: 80, saved_search: @ai, published_at: 1.hour.ago)
    get root_path(sort: "fit")
    assert_select "##{ActionView::RecordIdentifier.dom_id(job)} form[action=?] button", dismiss_job_posting_path(job), text: "Not interested"

    post dismiss_job_posting_path(job), params: { from: "list" }, headers: { "HTTP_REFERER" => root_url(sort: "fit") }
    assert_redirected_to root_url(sort: "fit")
    assert_equal "dismissed", job.reload.status
  end
end
