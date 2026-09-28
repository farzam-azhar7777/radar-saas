require "test_helper"

# The verdict leads the job page, so it must only ever say what the numbers
# beside it show.
class ClientSnapshotTest < ActiveSupport::TestCase
  def snap(**attrs) = ClientSnapshot.new(JobPosting.new(attrs))

  test "unverified payment is the verdict, whatever else is true" do
    v = snap(client_payment_verified: false, client_total_spent: 90_000, client_total_hires: 40, client_total_posted_jobs: 50).verdict
    assert_equal :bad, v.tone
    assert_match "Payment not verified", v.text
  end

  test "a first-time client says there is nothing to judge" do
    v = snap(client_payment_verified: true, client_total_spent: 0, client_total_hires: 0, client_total_posted_jobs: 0).verdict
    assert_equal :warn, v.tone
    assert_match "First job on Upwork", v.text
  end

  test "an established client who hires reads as good" do
    v = snap(client_payment_verified: true, client_total_spent: 48_000, client_total_hires: 12, client_total_posted_jobs: 15,
             client_rating: 4.9, client_total_reviews: 10).verdict
    assert_equal :good, v.tone
    assert_equal "Established client who hires.", v.text
  end

  test "a client who posts a lot and hires little is flagged with the numbers" do
    v = snap(client_payment_verified: true, client_total_spent: 3_000, client_total_hires: 2, client_total_posted_jobs: 20).verdict
    assert_equal :warn, v.tone
    assert_match "Posts often, hires rarely: 10% of 20 jobs", v.text
  end

  test "the job that prompted this: verified and hires, but tiny spend and no shared hours" do
    Profile.current.update!(timezone: "Asia/Karachi")
    v = snap(client_payment_verified: true, client_total_spent: 200, client_total_hires: 2, client_total_posted_jobs: 2,
             client_rating: 5.0, client_total_reviews: 1, client_timezone: "America/New_York").verdict
    assert_equal :warn, v.tone
    assert_equal "Hires when they post, but small budgets so far: $200 across 2 hires and no working hours in common with you.", v.text
  end

  test "hidden spend is shown as hidden, never as zero" do
    spent = snap(client_payment_verified: true, client_financial_privacy: true, client_total_spent: 0).readings.find { |r| r.label == "Spent" }
    assert_equal "Hidden", spent.value
  end

  test "readings carry what matters, each with its reason" do
    labels = snap(client_payment_verified: true, client_total_spent: 5_000, client_total_hires: 5, client_total_posted_jobs: 8,
                  client_rating: 4.6, client_total_reviews: 4, client_country: "USA", client_city: "Austin",
                  client_timezone: "America/Chicago").readings.map(&:label)
    assert_equal [ "Payment", "Spent", "Hire rate", "Rating", "Location", "Hours shared" ], labels
  end
end
