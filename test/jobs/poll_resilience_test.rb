require "test_helper"

# On 2026-09-10 at 10:07 Upwork's gateway answered a poll with plain text and
# JSON::ParserError escaped `rescue Upwork::Error`, failing the whole job. A
# poll cycle must survive anything the far end does to it.
class PollResilienceTest < ActiveSupport::TestCase
  class Failing
    def initialize(error) = @error = error
    def search_all(*) = raise(@error)
  end

  setup do
    SavedSearch.create!(name: "Rails", terms: [ "ruby on rails" ], threshold: 70, hot_threshold: 80, active: true)
  end

  # Swap the seam directly rather than pulling in a mocking library for one
  # method. JobSource.current is the single point Radar talks to Upwork through.
  def poll_with(error)
    source = Failing.new(error)
    original = JobSource.method(:current)
    JobSource.define_singleton_method(:current) { source }
    PollAllSearchesJob.new.perform
  ensure
    JobSource.define_singleton_method(:current, original)
  end

  test "an unhealthy gateway skips the cycle instead of failing the job" do
    assert_nothing_raised { poll_with(Upwork::TransportError.new("Upwork returned 503 but not JSON: upstream connect error")) }
  end

  test "rate limiting skips the cycle" do
    assert_nothing_raised { poll_with(Upwork::RateLimited.new("slow down")) }
  end

  test "an expired token skips the cycle rather than crashing the worker" do
    assert_nothing_raised { poll_with(Upwork::AuthError.new("Upwork rejected the token")) }
  end

  test "a GraphQL error skips the cycle" do
    assert_nothing_raised { poll_with(Upwork::Error.new("Underling search failed")) }
  end
end
