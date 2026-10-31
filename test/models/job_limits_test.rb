require "test_helper"

class JobLimitsTest < ActiveSupport::TestCase
  def posting(**attrs)
    JobPosting.new({ upwork_id: SecureRandom.hex(6), title: "Rails dev" }.merge(attrs))
  end

  def limits(raw) = JobLimits.new(raw)

  test "blank boxes are dropped and numbers are kept as numbers" do
    raw = { "hire_rate" => { "min" => "50", "max" => "" }, "bids" => { "min" => "", "max" => "" },
            "client_rating" => { "min" => "4.5" }, "nonsense" => { "min" => "3" } }
    assert_equal({ "hire_rate" => { "min" => 50 }, "client_rating" => { "min" => 4.5 } }, JobLimits.clean(raw))
  end

  test "one set of limits is saved for every search and read back" do
    assert_not JobLimits.current.any?

    assert limits("bids" => { "max" => "20" }).save
    assert_equal({ "bids" => { "max" => 20 } }, JobLimits.current.to_h)
  end

  test "a job inside every limit passes" do
    l = limits("hire_rate" => { "min" => 50 }, "bids" => { "max" => 20 }, "client_spent" => { "min" => 1000, "max" => 50_000 })
    assert_nil l.breach(posting(client_total_posted_jobs: 10, client_jobs_with_hires: 7, total_applicants: 12, client_total_spent: 8000))
  end

  test "each limit names the figure that broke it" do
    assert_equal "Client hire rate 30%, under your 50% minimum",
                 limits("hire_rate" => { "min" => 50 }).breach(posting(client_total_posted_jobs: 10, client_jobs_with_hires: 3))
    assert_equal "Bids so far 35, over your 20 maximum", limits("bids" => { "max" => 20 }).breach(posting(total_applicants: 35))
    assert_equal "Client total spent $120,000, over your $50,000 maximum",
                 limits("client_spent" => { "max" => 50_000 }).breach(posting(client_total_spent: 120_000))
  end

  test "an hourly range passes when any part of it is inside the limit" do
    l = limits("hourly_rate" => { "min" => 25, "max" => 60 })
    assert_nil l.breach(posting(hourly_min: 15, hourly_max: 30))
    assert_nil l.breach(posting(hourly_min: 50, hourly_max: 80))
    assert_equal "Hourly rate $20/hr, under your $25/hr minimum", l.breach(posting(hourly_min: 10, hourly_max: 20))
    assert_equal "Hourly rate $70/hr, over your $60/hr maximum", l.breach(posting(hourly_min: 70, hourly_max: 90))
  end

  test "a job with no figure for a stat is kept" do
    l = limits("hire_rate" => { "min" => 50 }, "client_rating" => { "min" => 4.5 }, "hourly_rate" => { "min" => 25 },
               "fixed_price" => { "min" => 500 })
    assert_nil l.breach(posting(fixed_amount: 800, hourly_min: 5)), "a fixed-price job has no hourly rate"
    assert_nil l.breach(posting(client_rating: 0)), "a client with no reviews has no rating yet"
    assert_nil l.breach(posting), "a new client has no hire rate yet"
  end

  test "a min above its max, a negative or a word is refused and not saved" do
    l = limits("bids" => { "min" => "30", "max" => "10" }, "hire_rate" => { "min" => "-5" }, "client_spent" => { "min" => "lots" })
    assert_not l.save
    assert_includes l.errors, "bids so far min must be at or below its max"
    assert_includes l.errors, "client hire rate min cannot be negative"
    assert_includes l.errors, "client total spent min must be a number"
    assert_not JobLimits.current.any?
  end

  test "the summary reads like a sentence" do
    l = limits("hire_rate" => { "min" => 50 }, "bids" => { "max" => 20 }, "client_spent" => { "min" => 1000, "max" => 50_000 })
    assert_equal [ "Bids so far at most 20", "Client hire rate at least 50%", "Client total spent $1,000 to $50,000" ], l.summary
  end

  test "impact counts what a set of limits would have passed over, and why" do
    jobs = [ posting(total_applicants: 40), posting(total_applicants: 45), posting(fixed_amount: 100), posting(total_applicants: 3) ]
    impact = limits("bids" => { "max" => 20 }, "fixed_price" => { "min" => 500 }).impact(jobs)

    assert_equal 4, impact[:total]
    assert_equal 3, impact[:passed_over]
    assert_equal [ [ "Bids so far", 2 ], [ "Fixed price", 1 ] ], impact[:by_stat]
  end

  test "the hourly minimum is also the scoring floor, falling back to the profile rate" do
    search = SavedSearch.new(name: "t", terms: [ "rails" ], threshold: 70)
    cheap = posting(title: "Rails", hourly_max: 30)
    note = -> { ScoreJobPosting.call(cheap, saved_search: search).reasons.find { |r| r["key"] == "budget" }["note"] }

    assert_equal "Pays up to $30/hr", note.call
    limits("hourly_rate" => { "min" => 40 }).save
    assert_equal "Tops out at $30/hr, under your $40 floor", note.call
  end
end
