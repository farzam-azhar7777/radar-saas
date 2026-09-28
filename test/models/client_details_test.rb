require "test_helper"

# "not seeing country of the person posting the job i.e. basically about the
# client section". Radar was already fetching totalPostedJobs, totalReviews,
# city and timezone from the API and throwing all four away.
class ClientDetailsTest < ActiveSupport::TestCase
  def posting(**attrs)
    JobPosting.new({ upwork_id: SecureRandom.hex(6), title: "Rails dev" }.merge(attrs))
  end

  # Upwork sends a full name for most postings and an ISO code for 17% of them.
  test "an ISO country code becomes a country name" do
    assert_equal "United States", CountryName.call("USA")
    assert_equal "Italy", CountryName.call("ITA")
    assert_equal "Pakistan", CountryName.call("PAK")
  end

  test "a name that is already a name is left alone" do
    assert_equal "United Kingdom", CountryName.call("United Kingdom")
  end

  test "an unknown code is handed back rather than blanked" do
    assert_equal "ZZZ", CountryName.call("ZZZ")
    assert_nil CountryName.call(nil)
    assert_nil CountryName.call("  ")
  end

  test "location joins city and country" do
    assert_equal "Pisa, Italy", posting(client_city: "Pisa", client_country: "ITA").client_location
    assert_equal "Italy", posting(client_country: "ITA").client_location
    assert_nil posting.client_location
  end

  # Upwork shows this as "100% hire rate". It separates a client who hires from
  # one who collects proposals.
  test "hire rate is hires over jobs posted" do
    assert_equal 100, posting(client_total_hires: 24, client_total_posted_jobs: 24).client_hire_rate
    assert_equal 50, posting(client_total_hires: 10, client_total_posted_jobs: 20).client_hire_rate
    assert_nil posting(client_total_hires: 5, client_total_posted_jobs: 0).client_hire_rate
  end

  test "average per hire needs both spend and hires" do
    assert_equal 941, posting(client_total_spent: 133_686, client_total_hires: 142).client_avg_per_hire
    assert_nil posting(client_total_spent: 5_000, client_total_hires: 0).client_avg_per_hire
    assert_nil posting(client_total_spent: 0, client_total_hires: 3).client_avg_per_hire
  end

  # He is in Lahore. A long-term role with no overlap is not workable, and
  # Upwork's own panel does not tell you this.
  test "overlap is counted against a Lahore working day" do
    assert_equal 9, posting(client_timezone: "Asia/Karachi").client_overlap_hours
    assert_equal 0, posting(client_timezone: "America/Chicago").client_overlap_hours
    assert_operator posting(client_timezone: "Europe/London").client_overlap_hours, :>, 0
  end

  test "a missing or nonsense timezone does not raise" do
    assert_nil posting.client_overlap_hours
    assert_nil posting(client_timezone: "Not/AZone").client_overlap_hours
    assert_nil posting(client_timezone: "Not/AZone").client_local_time
  end

  test "the inbox row names the country" do
    label = posting(client_country: "ITA", client_total_spent: 7800, client_total_hires: 24,
                    client_rating: 5.0, client_payment_verified: true).client_label
    assert_match "Italy", label
    assert_match "$7800 spent", label
  end
end
