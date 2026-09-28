require "test_helper"

class ScoreJobPostingTest < ActiveSupport::TestCase
  def search(**overrides)
    SavedSearch.new({ name: "t", terms: [ "rails" ], threshold: 70, min_hourly: 25,
                      excluded_keywords: [ "wordpress" ] }.merge(overrides))
  end

  def posting(**overrides)
    JobPosting.new({
      upwork_id: "x", title: "Ruby on Rails developer",
      description: "Rails, PostgreSQL, Hotwire, Sidekiq, Stripe multi-tenant SaaS",
      hourly_max: 40, client_payment_verified: true, client_total_spent: 60_000,
      client_total_hires: 20, client_rating: 4.9, published_at: 10.minutes.ago
    }.merge(overrides))
  end

  test "a strong Rails post clears the threshold" do
    assert ScoreJobPosting.call(posting, saved_search: search).score >= 70
  end

  test "an excluded keyword zeroes the score and says so" do
    result = ScoreJobPosting.call(posting(description: "WordPress theme work"), saved_search: search)
    assert_equal 0, result.score
    assert_match(/Excluded by keyword/, result.reasons.first["note"])
  end

  test "an unrelated post scores low" do
    unrelated = posting(title: "Logo design", description: "Need a logo in Figma", hourly_max: 10)
    assert_operator ScoreJobPosting.call(unrelated, saved_search: search).score, :<, 70
  end

  test "every reason carries points, max and a human note" do
    ScoreJobPosting.call(posting, saved_search: search).reasons.each do |r|
      assert r["note"].present?, "reason #{r['key']} has no note"
      assert r["max"].to_i.positive?
    end
  end

  test "an older post loses recency points" do
    fresh = ScoreJobPosting.call(posting, saved_search: search).score
    stale = ScoreJobPosting.call(posting(published_at: 5.days.ago), saved_search: search).score
    assert_operator stale, :<, fresh
  end
end

class BestSearchForTest < ActiveSupport::TestCase
  def rails_search
    SavedSearch.new(id: 1, name: "Ruby on Rails", terms: [ "ruby on rails", "rails" ],
                    threshold: 70, hot_threshold: 80, excluded_keywords: [])
  end

  def generic_search
    SavedSearch.new(id: 2, name: "Full stack / web dev",
                    terms: [ "web application", "web developer", "full stack developer" ],
                    threshold: 70, hot_threshold: 90, excluded_keywords: [])
  end

  test "a Rails job caught by the generic search is re-homed to the Rails search" do
    posting = JobPosting.new(title: "Ruby on Rails Developer for Web Application",
                             description: "Rails, PostgreSQL")
    owner = BestSearchFor.call(posting, fallback: generic_search,
                               searches: [ generic_search, rails_search ])
    assert_equal "Ruby on Rails", owner.name
  end

  test "a genuinely generic job stays with the generic search" do
    posting = JobPosting.new(title: "Web Developer needed", description: "PHP and jQuery site")
    owner = BestSearchFor.call(posting, fallback: generic_search,
                               searches: [ generic_search, rails_search ])
    assert_equal "Full stack / web dev", owner.name
  end

  test "no matching search falls back to the one that pulled it" do
    posting = JobPosting.new(title: "Logo design", description: "Figma")
    owner = BestSearchFor.call(posting, fallback: generic_search,
                               searches: [ generic_search, rails_search ])
    assert_equal generic_search, owner
  end
end

class TextMatchTest < ActiveSupport::TestCase
  test "hyphenated titles match spaced terms" do
    hay = TextMatch.normalize("Senior Full-Stack Developer wanted")
    assert TextMatch.includes?(hay, "full stack developer")
  end

  test "slashes and punctuation do not break matching" do
    hay = TextMatch.normalize("Ruby/Rails engineer, senior-level")
    assert TextMatch.includes?(hay, "rails")
    assert TextMatch.includes?(hay, "ruby")
  end

  test "collapsed whitespace matches" do
    assert TextMatch.includes?(TextMatch.normalize("Full  Stack   Developer"), "full stack developer")
  end

  test "normalization keeps version-ish tokens intact" do
    hay = TextMatch.normalize("Rails 8.1 and C# and Next.js")
    assert TextMatch.includes?(hay, "rails 8.1")
    assert TextMatch.includes?(hay, "next.js")
  end
end

class UpworkClientTest < ActiveSupport::TestCase
  test "net/http constants resolve inside the Upwork namespace" do
    assert_nothing_raised { ::Net::HTTP }
    assert_equal "https://api.upwork.com/graphql", Upwork::Client::GRAPHQL_URL
  end

  test "token exchange fails loudly when credentials were never configured" do
    skip "credentials are configured" if Upwork::Client.configured?

    error = assert_raises(Upwork::AuthError) { Upwork::Client.new.exchange_code("x") }
    assert_match(/No Upwork API key saved/, error.message)
  end
end

# Regressions found by running against live Upwork data on 2026-09-08.
class ScoringRegressionTest < ActiveSupport::TestCase
  def rails_search
    SavedSearch.new(name: "Ruby on Rails", terms: [ "ruby on rails", "rails", "ror" ],
                    threshold: 70, hot_threshold: 70, min_hourly: 25, min_fixed: 500,
                    excluded_keywords: [], excluded_countries: [])
  end

  def posting(**over)
    JobPosting.new({ upwork_id: "x", title: "t", description: "", published_at: 20.minutes.ago }.merge(over))
  end

  test "a job titled Senior Ruby on Rails Engineer clears the threshold" do
    p = posting(title: "Senior Ruby on Rails Engineer",
                description: "Ruby on Rails, React, PostgreSQL on a mature product.",
                client_payment_verified: true, client_total_spent: 140_000, client_rating: 5.0,
                client_total_hires: 20)
    assert_operator ScoreJobPosting.call(p, saved_search: rails_search).score, :>=, 70
  end

  test "prose mentioning rails does not make a hardware job a Rails job" do
    p = posting(title: "Embedded Hardware Engineer for nRF52840 Sleep Current",
                description: "Mount the board on DIN rails. Next, measure sleep current.",
                fixed_amount: 500, client_payment_verified: true)
    result = ScoreJobPosting.call(p, saved_search: rails_search)
    assert_operator result.score, :<, 70
    assert_equal 0, result.reasons.find { |r| r["key"] == "title_match" }["points"]
  end

  test "a twenty dollar fixed job cannot score full marks on budget" do
    p = posting(title: "Ruby on Rails developer", description: "Rails work", fixed_amount: 20)
    budget = ScoreJobPosting.call(p, saved_search: rails_search).reasons.find { |r| r["key"] == "budget" }
    assert_equal 0, budget["points"], "a $20 job should earn nothing on budget"
  end

  test "word boundaries stop ror matching error" do
    hay = TextMatch.normalize("We keep hitting an error in the mirror module")
    assert_not TextMatch.includes?(hay, "ror")
    assert TextMatch.includes?(TextMatch.normalize("Looking for a RoR developer"), "ror")
  end
end

class ExpressionBucketTest < ActiveSupport::TestCase
  # Upwork rejects a searchExpression over roughly 340 characters.
  test "buckets stay under the length ceiling" do
    searches = [ SavedSearch.new(terms: (1..60).map { |i| "some longer search phrase #{i}" }) ]
    buckets = JobSource::Live.new(client: nil).expression_buckets(searches)
    assert_operator buckets.size, :>, 1
    buckets.each { |b| assert_operator b.length, :<=, JobSource::Live::MAX_EXPRESSION }
  end

  test "multi word terms are quoted and single words are not" do
    b = JobSource::Live.new(client: nil).expression_buckets([ SavedSearch.new(terms: [ "ruby on rails", "ror" ]) ])
    assert_equal %("ruby on rails" OR ror), b.first
  end

  test "each search gets its own query so a broad one cannot crowd out a narrow one" do
    rails = SavedSearch.new(terms: [ "ruby on rails" ])
    web   = SavedSearch.new(terms: [ "web development" ])
    buckets = JobSource::Live.new(client: nil).expression_buckets([ rails, web ])
    assert_equal 2, buckets.size
    assert_equal %("ruby on rails"), buckets.first
    assert_equal %("web development"), buckets.last
  end
end

class InboxSearchAndSortTest < ActiveSupport::TestCase
  def make(**over)
    JobPosting.create!({ upwork_id: SecureRandom.hex(6), title: "Rails developer",
                         description: "Build things", status: "matched", score: 50,
                         published_at: 1.hour.ago }.merge(over))
  end

  setup do
    @old  = make(title: "Ruby on Rails engineer", score: 90, total_applicants: 40,
                 hourly_max: 30, published_at: 5.days.ago, skills: [ "Ruby on Rails" ])
    @new  = make(title: "Next.js developer in Poland", score: 60, total_applicants: 2,
                 fixed_amount: 9000, published_at: 2.minutes.ago, client_country: "Poland")
    @mid  = make(title: "Django engineer", score: 75, total_applicants: nil,
                 hourly_max: 55, published_at: 1.day.ago)
  end

  test "newest first" do
    assert_equal @new, JobPosting.where(status: "matched").sorted_by("newest").first
  end

  test "best fit first" do
    assert_equal @old, JobPosting.where(status: "matched").sorted_by("fit").first
  end

  test "fewest bids first, and unknown bid counts sink rather than lead" do
    order = JobPosting.where(status: "matched").sorted_by("competition").to_a
    assert_equal @new, order.first
    assert_equal @mid, order.last, "a nil applicant count must not sort as zero"
  end

  test "best paid first across fixed and hourly" do
    assert_equal @new, JobPosting.where(status: "matched").sorted_by("budget").first
  end

  test "an unknown sort key falls back to newest instead of blowing up" do
    assert_equal @new, JobPosting.where(status: "matched").sorted_by("nonsense").first
  end

  test "search covers title, skills and country" do
    assert_includes JobPosting.matching("ruby on rails"), @old
    assert_includes JobPosting.matching("poland"), @new
    assert_empty JobPosting.matching("zzzznothing")
  end

  test "a blank search returns everything" do
    assert_equal JobPosting.count, JobPosting.matching("").count
    assert_equal JobPosting.count, JobPosting.matching(nil).count
  end
end

class TransportResilienceTest < ActiveSupport::TestCase
  # A network blip killed a whole poll cycle on 2026-09-08 at 23:52.
  test "a timed-out query is skipped rather than raised" do
    flaky = Object.new
    def flaky.query(*) = raise(Upwork::TransportError, "Net::ReadTimeout")

    rows = JobSource::Live.new(client: flaky).search_all([ SavedSearch.new(terms: [ "rails" ]) ])
    assert_equal [], rows
  end

  test "transport failures are classified as Upwork errors so callers catch them" do
    assert Upwork::TransportError.ancestors.include?(Upwork::Error)
    assert_includes Upwork::TRANSPORT_FAILURES, Net::ReadTimeout
  end
end

# The one link that live traffic has not exercised yet, because no new Rails
# job has been posted since auto-write was switched on.
class AutoGenerationDecisionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Setting.set(Setting::AUTO_GENERATE, "on")
    @writes  = SavedSearch.create!(name: "Writes #{SecureRandom.hex(3)}", terms: [ "rails" ],
                                   threshold: 70, hot_threshold: 70, auto_generate: true)
    @notifies = SavedSearch.create!(name: "Notifies #{SecureRandom.hex(3)}", terms: [ "full stack" ],
                                    threshold: 70, hot_threshold: 70, auto_generate: false)
  end

  def hot_posting(search)
    JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails developer",
                       status: "matched", score: 90, saved_search: search,
                       published_at: 2.minutes.ago)
  end

  test "a hot job on an auto-writing search is queued for a proposal" do
    posting = hot_posting(@writes)
    assert posting.hot?, "fixture should be hot"

    assert_enqueued_with(job: GenerateProposalJob) do
      PollAllSearchesJob.new.send(:generate, [ posting ])
    end
    assert posting.reload.generation_queued_at.present?
  end

  test "a hot job on a notify-only search is never queued" do
    posting = hot_posting(@notifies)

    assert_no_enqueued_jobs(only: GenerateProposalJob) do
      PollAllSearchesJob.new.send(:generate, [ posting ])
    end
    assert_nil posting.reload.generation_queued_at
  end

  test "the auto-write switch stops queueing even for an auto-writing search" do
    Setting.set(Setting::AUTO_GENERATE, "off")
    posting = hot_posting(@writes)

    assert_no_enqueued_jobs(only: GenerateProposalJob) do
      PollAllSearchesJob.new.send(:generate, [ posting ])
    end
  end

  test "the daily cap stops queueing once reached" do
    posting = hot_posting(@writes)
    original = ENV["RADAR_DAILY_GENERATION_CAP"]
    ENV["RADAR_DAILY_GENERATION_CAP"] = "0"
    begin
      assert_no_enqueued_jobs(only: GenerateProposalJob) do
        PollAllSearchesJob.new.send(:generate, [ posting ])
      end
    ensure
      ENV["RADAR_DAILY_GENERATION_CAP"] = original
    end
  end
end
