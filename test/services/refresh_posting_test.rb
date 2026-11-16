require "test_helper"

class RefreshPostingTest < ActiveSupport::TestCase
  class StubSource
    attr_reader :expressions

    def initialize(rows, title: nil) = (@rows = rows; @title = title; @expressions = [])

    def current_title(_id) = @title

    def fetch(expression, _page)
      @expressions << expression
      @rows.fetch(expression, [])
    end
  end

  setup do
    @search = SavedSearch.create!(name: "S#{SecureRandom.hex(3)}", terms: [ "rails" ],
                                  threshold: 70, hot_threshold: 70)
    @posting = JobPosting.create!(
      upwork_id: "job-1", title: "Senior Full-Stack Developer for Car Rental Platform",
      description: "Ruby on Rails and React work on a rental platform.", status: "matched",
      score: 80, total_applicants: 0, published_at: 30.minutes.ago, saved_search: @search
    )
  end

  def row(**over)
    { "upwork_id" => "job-1", "total_applicants" => 30 }.merge(over)
  end

  test "a rising bid count is picked up and reported in plain terms" do
    source = StubSource.new({ %q{"Car Rental Platform"} => [ row ] })
    result = RefreshPosting.call(@posting, source: source)

    assert result.found
    assert_equal [ 0, 30 ], result.changes["total_applicants"]
    assert_equal 30, @posting.reload.total_applicants
    assert_match(/Now 30 bids, up 30/, result.message)
  end

  test "the first refresh records what the count was at discovery" do
    source = StubSource.new({ %q{"Car Rental Platform"} => [ row ] })
    RefreshPosting.call(@posting, source: source)
    assert_equal 0, @posting.reload.applicants_at_discovery
  end

  test "generic role words are skipped when building the search phrase" do
    source = StubSource.new({})
    RefreshPosting.call(@posting, source: source)

    assert_equal %q{"Car Rental Platform"}, source.expressions.first,
                 "Senior, Full-Stack, Developer and for identify nothing"
  end

  test "a job that cannot be found says so rather than pretending" do
    result = RefreshPosting.call(@posting, source: StubSource.new({}))

    assert_not result.found
    assert_match(/may have been closed or filled/, result.message)
    assert_nil @posting.reload.refreshed_at
  end

  test "no change is reported honestly" do
    source = StubSource.new({ %q{"Car Rental Platform"} => [ row("total_applicants" => 0) ] })
    assert_equal "Nothing has changed.", RefreshPosting.call(@posting, source: source).message
  end

  test "more competition rescores the job, because the shape may change" do
    source = StubSource.new({ %q{"Car Rental Platform"} => [ row("total_applicants" => 400) ] })
    RefreshPosting.call(@posting, source: source)

    assert_equal 400, @posting.reload.total_applicants
    assert_equal "C", ProposalArchetype.new(@posting).key, "400 bids is the high-competition shape"
  end

  test "Upwork telling us he already applied is surfaced" do
    source = StubSource.new({ %q{"Car Rental Platform"} => [ row("already_applied" => true) ] })
    result = RefreshPosting.call(@posting, source: source)

    assert @posting.reload.already_applied
    assert_match(/already applied/, result.message)
  end

  test "a transport failure does not raise into the controller" do
    broken = Object.new
    def broken.fetch(*) = raise(Upwork::TransportError, "Net::ReadTimeout")

    result = RefreshPosting.call(@posting, source: broken)
    assert_not result.found
    assert_match(/did not answer/, result.message)
  end

  test "a job the client renamed is found again by asking Upwork for its title, and the new title is kept" do
    source = StubSource.new({ %q{"Rails Fleet Booking"} => [ row ] }, title: "Rails Engineer: Fleet Booking Engine")
    result = RefreshPosting.call(@posting, source: source)

    assert result.found
    assert_equal "Rails Engineer: Fleet Booking Engine", @posting.reload.title
    assert_match "Upwork renamed this job to “Rails Engineer: Fleet Booking Engine”. Saved. Now 30 bids", result.message

    @posting.update!(title: "Senior Full-Stack Developer for Car Rental Platform")
    source = StubSource.new({ %q{"Rails Fleet Booking"} => [ row("already_applied" => true) ] }, title: "Rails Engineer: Fleet Booking Engine")
    assert_equal "Upwork renamed this job to “Rails Engineer: Fleet Booking Engine”. Saved. You have already applied to this one.",
                 RefreshPosting.call(@posting, source: source).message
  end

  test "a renamed job whose bids cannot be found still gets its new title" do
    result = RefreshPosting.call(@posting, source: StubSource.new({}, title: "Fleet Booking Engine"))
    assert_not result.found
    assert_equal "Fleet Booking Engine", @posting.reload.title
    assert_match "renamed this job", result.message
  end

  test "a job that is simply gone says so, and keeps its title" do
    result = RefreshPosting.call(@posting, source: StubSource.new({}))
    assert_match "Could not find this job on Upwork", result.message
    assert_equal "Senior Full-Stack Developer for Car Rental Platform", @posting.reload.title
  end
end
