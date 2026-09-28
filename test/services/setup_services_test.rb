require "test_helper"

class SetupServicesTest < ActiveSupport::TestCase
  test "Claude missing, signed out, or unable to use the writer's model are three different fixes" do
    Setting.set(Setting::CLAUDE_PATH, "/no/such/claude")
    result = ClaudeCheck.call
    assert_not result.ok?
    assert_equal :install, result.fix
    Setting.clear(Setting::CLAUDE_PATH)

    with_claude(ClaudeRun::Error.new("claude exited 1: Invalid API key. Please run /login")) do
      stub_version { assert_equal :login, ClaudeCheck.call.fix }
    end

    calls = 0
    reply = ->(_) { calls += 1; calls == 1 ? "OK" : ClaudeRun::Error.new("model not available on your plan") }
    with_claude(reply) do
      stub_version do
        result = ClaudeCheck.call
        assert result.signed_in
        assert_not result.model_ok
        assert_equal :model, result.fix
      end
    end
  end

  test "a working Claude passes, and the model check uses the writer's model" do
    with_claude("OK") do |calls|
      stub_version { assert ClaudeCheck.call.ok? }
      assert_equal Radar.writer_model, calls.last[:opts][:model]
    end
  end

  test "the address Upwork sends back gives up its code in every shape people paste" do
    assert_equal "abc", Upwork::Client.code_from("https://x.test/cb?code=abc&state=1")
    assert_equal "abc", Upwork::Client.code_from("  https://x.test/cb?state=1&code=abc#frag ")
    assert_equal "abc-123", Upwork::Client.code_from("abc-123")
    assert_nil Upwork::Client.code_from("https://x.test/cb?state=1")
    assert_nil Upwork::Client.code_from("two words")
  end

  test "a preview scores the latest results exactly as the poller would" do
    now = Time.current
    rows = [
      { "upwork_id" => "1", "title" => "Senior Ruby on Rails developer", "description" => "Rails, Stripe, Sidekiq, PostgreSQL",
        "hourly_max" => 60, "client_payment_verified" => true, "client_total_spent" => 50_000, "client_total_hires" => 10,
        "client_rating" => 4.9, "published_at" => (now - 1.hour).iso8601 },
      { "upwork_id" => "2", "title" => "Logo design", "description" => "Figma", "published_at" => (now - 5.hours).iso8601 }
    ]
    search = SavedSearch.new(name: "Rails", terms: [ "rails" ], threshold: 60, hot_threshold: 95, min_hourly: 25)
    preview = SearchPreview.new(search)
    preview.define_singleton_method(:fetch) { |*| rows }

    result = preview.call
    assert result.ok?
    assert_equal 2, result.seen
    assert_equal 1, result.inbox
    assert_equal 0, result.hot
    assert_equal "Senior Ruby on Rails developer", result.examples.first[:title]
    assert_equal 10, result.per_day, "2 jobs over 5 hours is about 10 a day"
  end

  test "a preview with no words asks for some" do
    assert_match "at least one word", SearchPreview.call(SavedSearch.new(terms: [])).error
  end

  test "the token file is per test process and clears cleanly" do
    store = Upwork::TokenStore.new
    assert_match "upwork_tokens_test_", store.path.to_s
    store.save!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now)
    assert store.connected?
    store.clear!
    assert_not Upwork::TokenStore.new.connected?
  end

  def stub_version
    original = ClaudeRun.method(:version)
    ClaudeRun.define_singleton_method(:version) { |*| "2.1.273 (Claude Code)" }
    yield
  ensure
    ClaudeRun.define_singleton_method(:version, original)
  end
end
