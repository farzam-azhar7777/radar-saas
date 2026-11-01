require "test_helper"

class EarlierCopiesTest < ActiveSupport::TestCase
  setup do
    @search = SavedSearch.create!(name: "Any", terms: [ "engineer" ], threshold: 0, hot_threshold: 0)
  end

  def row(id, title: "Web3/Blockchain Engineer", country: "Philippines", posted: 1, spent: 0, **extra)
    { "upwork_id" => id, "title" => title, "description" => "Build a dapp.", "client_country" => country,
      "client_total_posted_jobs" => posted, "client_total_spent" => spent, "published_at" => Time.current.iso8601 }.merge(extra)
  end

  def ingest(*rows) = IngestPostings.call(rows, searches: [ @search ])

  def job(id) = JobPosting.find_by!(upwork_id: id)

  test "the second posting is tagged and kept, the third is passed over with the earlier unwritten copy" do
    ingest(row("a", posted: 1))
    ingest(row("b", title: "Web3/ Blockchain Engineer", posted: 2))

    assert_equal [ 1, job("a").id, "matched" ], [ job("b").repost_count, job("b").repost_of_id, job("b").status ]
    assert_equal "Posted 2 times", job("b").repost_label

    ingest(row("c", title: "Web3/block chain engineer", posted: 3))

    assert_equal [ 2, job("a").id, "ignored" ], [ job("c").repost_count, job("c").repost_of_id, job("c").status ]
    assert_equal %w[ignored ignored], [ job("a").status, job("b").status ], "earlier unwritten copies leave the inbox too"
    assert_match(/\APosted 3 times since .+ often not really hiring\.\z/, job("a").score_reasons.last["note"])
  end

  test "a copy already written or being written stays where it is" do
    ingest(row("a"))
    job("a").proposals.create!(version: 1, body: "x", generated_at: Time.current)
    ingest(row("b", posted: 2))
    job("b").update!(generation_queued_at: Time.current)
    ingest(row("c", posted: 3))

    assert_equal %w[matched matched ignored], %w[a b c].map { |id| job(id).status }
  end

  test "a country code and its name are the same client" do
    ingest(row("a", country: "ITA"))
    ingest(row("b", country: "Italy", posted: 2))
    assert_equal 1, job("b").repost_count
  end

  test "different clients, different jobs and stale postings are not reposts" do
    ingest(row("a", posted: 5, spent: 900))
    ingest(row("other-country", country: "Kenya", posted: 6, spent: 900))
    ingest(row("fewer-posts", posted: 4, spent: 900))
    ingest(row("less-spent", posted: 6, spent: 100))
    ingest(row("busy-client", posted: 90, spent: 900))
    ingest(row("other-role", title: "Product Owner (Mid Level)", posted: 6, spent: 900))

    assert_equal [ 0 ], JobPosting.where.not(upwork_id: "a").distinct.pluck(:repost_count)
  end

  test "a job from more than 30 days back does not count" do
    ingest(row("a"))
    job("a").update_column(:created_at, 31.days.ago)
    ingest(row("b", posted: 2))
    assert_not job("b").reposted?
  end

  test "the backfill flags jobs already seen and clears the inbox of ones posted too often" do
    ingest(row("a"))
    ingest(row("b", posted: 2))
    ingest(row("c", posted: 3))
    JobPosting.update_all(repost_of_id: nil, repost_count: 0, status: "matched")

    Rails.application.load_tasks unless Rake::Task.task_defined?("radar:flag_reposts")
    assert_output(/Flagged 2 reposts\. Passed over 3 unwritten inbox jobs\./) { Rake::Task["radar:flag_reposts"].execute }

    assert_equal [ 0, 1, 2 ], %w[a b c].map { |id| job(id).repost_count }
  end
end
