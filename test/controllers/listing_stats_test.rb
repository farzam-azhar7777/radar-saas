require "test_helper"

class ListingStatsTest < ActionDispatch::IntegrationTest
  setup do
    @search = SavedSearch.create!(name: "AI", terms: [ "ai" ], threshold: 50, hot_threshold: 90)
  end

  def job(**attrs)
    JobPosting.create!({ upwork_id: SecureRandom.hex(6), title: "Voice agent", status: "matched", score: 75, saved_search: @search,
                         published_at: 1.hour.ago }.merge(attrs))
  end

  def row(posting) = "##{ActionView::RecordIdentifier.dom_id(posting)}"

  test "the inbox row carries the job and client facts from the job page, coloured the same way" do
    posting = job(duration_label: "1 to 3 months", screening_questions: [ "Similar project?", "Availability?" ],
                  client_payment_verified: false, client_total_spent: 25_000, client_total_hires: 9,
                  client_total_posted_jobs: 10, client_jobs_with_hires: 2, client_rating: 4.9)
    get root_path

    assert_select row(posting) do
      assert_select "p", text: /1 to 3 months.*2 questions.*AI/m
      assert_select ".client-glance .text-signal", "Payment not verified"
      assert_select ".client-glance .text-good", "$25k spent"
      assert_select ".client-glance .text-warn", "20% hire rate"
      assert_select ".client-glance .text-good", "4.9 rating"
      assert_select ".client-glance[title*=?]", "Payment not verified"
    end
  end

  test "a row with no client facts shows no empty client line" do
    posting = job
    get root_path
    assert_select "#{row(posting)} .client-glance", 0
  end
end
