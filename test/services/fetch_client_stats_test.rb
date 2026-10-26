require "test_helper"

class FetchClientStatsTest < ActiveSupport::TestCase
  class FakeUpwork
    def initialize(response)
      @response = response
    end

    def query(*)
      raise @response if @response.is_a?(Exception)

      @response
    end
  end

  BUYER = { "jobPubDetails" => { "buyer" => { "stats" => { "totalJobsWithHires" => 9 },
                                              "jobs" => { "postedCount" => 14, "openCount" => 1 } } } }.freeze

  def posting = JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails dev", client_total_hires: 18, client_total_posted_jobs: 13)

  test "the live source reads Upwork's own hiring figures for the client" do
    stats = JobSource::Live.new(client: FakeUpwork.new(BUYER)).client_stats("123")
    assert_equal({ "client_total_posted_jobs" => 14, "client_jobs_with_hires" => 9, "client_open_jobs" => 1 }, stats)
  end

  test "each matched posting gets the client's figures, and the hire rate matches Upwork" do
    job = posting
    FetchClientStats.call([ job ], source: JobSource::Live.new(client: FakeUpwork.new(BUYER)))

    job.reload
    assert_equal [ 14, 9, 1 ], [ job.client_total_posted_jobs, job.client_jobs_with_hires, job.client_open_jobs ]
    assert_equal 65, job.client_hire_rate
  end

  test "an Upwork failure leaves the posting as it was and never stops the poll" do
    job = posting
    assert_nothing_raised do
      FetchClientStats.call([ job ], source: JobSource::Live.new(client: FakeUpwork.new(Upwork::Error.new("not allowed"))))
    end
    assert_nil job.reload.client_jobs_with_hires
    assert_nil job.client_hire_rate
  end
end
