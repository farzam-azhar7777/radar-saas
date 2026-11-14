require "test_helper"

class JobSearchTest < ActionDispatch::IntegrationTest
  def job(title, **attrs)
    JobPosting.create!({ upwork_id: SecureRandom.hex(6), title: title, status: "matched", score: 70, published_at: 1.day.ago }.merge(attrs))
  end

  test "every page has the Find a job button and the search box behind Cmd+K" do
    get root_path
    assert_select "button[data-action='command-palette#open']", text: /Find a job/
    assert_select "dialog[data-command-palette-target=dialog] input[data-command-palette-target=input]"
  end

  test "it finds jobs wherever they are, says where, and links to each job's page" do
    applied = job("Voice agent for a call center", status: "applied", applied_at: 2.days.ago)
    passed = job("Voice bot follow-up", status: "ignored")
    pasted = job("Voice IVR rebuild", source: "pasted", upwork_id: "pasted-abc")
    job("Shopify theme fixes")

    get job_search_path(q: "voice")
    assert_response :success
    assert_no_match "<html", response.body
    assert_select "a[data-command-palette-target=item]", 3
    { applied => "Applied", passed => "Passed over", pasted => "Pasted jobs" }.each do |posting, place|
      assert_select "a[href=?] .chip", job_posting_path(posting), text: place
    end
  end

  test "title matches come before matches only in the description" do
    in_text = job("Backend work", description: "We use a voice agent", published_at: 1.hour.ago)
    in_title = job("Voice agent", published_at: 5.days.ago)

    get job_search_path(q: "voice")
    hrefs = css_select("a[data-command-palette-target=item]").map { |a| a["href"] }
    assert_equal [ job_posting_path(in_title), job_posting_path(in_text) ], hrefs
  end

  test "an Upwork link finds that exact job" do
    target = job("Voice agent", upwork_id: "2117183674717185074")
    job("Another voice agent")

    get job_search_path(q: "https://www.upwork.com/jobs/Voice-agent_~022117183674717185074/?referrer=x")
    assert_select "a[data-command-palette-target=item]", 1
    assert_select "a[href=?]", job_posting_path(target)
  end

  test "too short a query, or no match, says so" do
    get job_search_path(q: "v")
    assert_match "Type a title", response.body
    get job_search_path(q: "zzzz")
    assert_match "No job in Radar matches", response.body
  end

  test "among title matches, jobs you applied to come first" do
    newer = job("Voice agent rebuild", published_at: 1.hour.ago)
    applied = job("Voice agent", status: "applied", applied_at: 1.day.ago, published_at: 5.days.ago)

    get job_search_path(q: "voice")
    assert_equal [ job_posting_path(applied), job_posting_path(newer) ], css_select("a[data-command-palette-target=item]").map { |a| a["href"] }
  end
end
