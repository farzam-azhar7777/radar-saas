require "test_helper"

# Eight of the first hundred postings Radar wrote for were restricted to a
# country Farzam is not in, and every one had Upwork's mandatory flag set to
# false, so nothing stopped them. That was $4.70 spent on jobs asking for
# Wroclaw, Canada and LatAm timezones.
class LocationSkipTest < ActiveSupport::TestCase
  def posting(locations, mandatory: false)
    JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails dev", status: "matched", score: 85,
                       preferred_locations: locations, preferred_location_mandatory: mandatory,
                       detail_fetched_at: Time.current)
  end

  test "a country list without Pakistan is a mismatch even when not mandatory" do
    assert posting([ "Poland" ]).location_mismatch?
    assert posting([ "Colombia", "Argentina", "Brazil" ]).location_mismatch?
  end

  test "his own country, worldwide, or no list at all is fine" do
    assert_not posting([ "Pakistan" ]).location_mismatch?
    assert_not posting([ "India", "Pakistan" ]).location_mismatch?
    assert_not posting([ "Worldwide" ]).location_mismatch?
    assert_not posting([]).location_mismatch?
    assert_not posting(nil).location_mismatch?
  end

  test "the mandatory flag still hard-filters at ingest" do
    assert posting([ "Poland" ], mandatory: true).location_blocked?
    assert_not posting([ "Poland" ]).location_blocked?, "not mandatory is not a hard block"
  end

  test "an automatic generation spends nothing on a restricted job" do
    p = posting([ "Poland" ])
    GenerateProposalJob.new.perform(p)

    assert_equal 0, p.proposals.count, "no proposal, so no money"
    assert_equal "matched", p.reload.status, "not a failure, it just was not written"
    assert_match "Poland", p.generation_error
    assert_nil p.generation_queued_at
  end

  # Never let a test shell out to claude -p: it costs real money and minutes.
  # Swapping the generator proves the guard was passed without invoking it.
  def with_stubbed_generator
    called = false
    # sections empty, so the job falls back to deriving them from the body:
    # exactly the path a real generation takes when the markers are ignored.
    result = Struct.new(:body, :duration_ms, :meta, :archetype, :checks, :attempts, :sections)
               .new("a written proposal", 1000, {}, "A", { "passed" => true }, 1, [])
    original = ProposalGenerator.method(:call)
    ProposalGenerator.define_singleton_method(:call) { |*, **| called = true; result }
    yield
    called
  ensure
    ProposalGenerator.define_singleton_method(:call, original)
  end

  test "pressing the button overrides it, because that is a decision to bid" do
    p = posting([ "Poland" ])
    called = with_stubbed_generator { GenerateProposalJob.new.perform(p, force: true) }

    assert called, "force must get past the location guard and reach the generator"
    assert_equal 1, p.proposals.count
  end

  test "without force the generator is never reached, so nothing is spent" do
    p = posting([ "Poland" ])
    called = with_stubbed_generator { GenerateProposalJob.new.perform(p) }

    assert_not called, "the guard must stop before the generator costs anything"
    assert_equal 0, p.proposals.count
  end
end
