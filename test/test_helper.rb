ENV["RAILS_ENV"] ||= "test"
# Every test process gets its own career folder, so nothing a test writes can
# land in a real one, and parallel workers cannot see each other's files.
ENV["RADAR_CAREER_PATH"] ||= File.expand_path("../tmp/test-career", __dir__)

require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    CAREER_FIXTURE = Rails.root.join("test", "fixtures", "files", "career")

    # The invented career in test/fixtures/files/career, which scoring tests
    # rely on. Tests used to read the author's real career repo by accident.
    def self.install_career_fixture!
      FileUtils.rm_rf(Radar.career_path)
      FileUtils.mkdir_p(Radar.career_path)
      FileUtils.cp_r("#{CAREER_FIXTURE}/.", Radar.career_path)
      CareerData.reload!
    end

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    parallelize_setup do |worker|
      ENV["RADAR_CAREER_PATH"] = Rails.root.join("tmp", "test-career-#{worker}").to_s
      install_career_fixture!
    end

    # Serial runs (a single file, or one worker) never call parallelize_setup.
    install_career_fixture!

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def install_career_fixture! = self.class.install_career_fixture!

    # Replaces the model for the duration of a block. The reply can be a
    # string or a lambda of the prompt; every call is recorded so a test can
    # assert on what the model was told and where it was allowed to look.
    def with_claude(reply = "ok")
      calls = []
      original = ClaudeRun.method(:call)
      ClaudeRun.define_singleton_method(:call) do |prompt, **opts|
        calls << { prompt: prompt, opts: opts }
        text = reply.respond_to?(:call) ? reply.call(prompt) : reply
        raise text if text.is_a?(Exception)

        ClaudeRun::Result.new(text: text, duration_ms: 10, meta: { "total_cost_usd" => 0.01 })
      end
      yield calls
    ensure
      ClaudeRun.define_singleton_method(:call, original)
    end

    # An empty career folder, for tests that build one from nothing.
    def reset_career!
      FileUtils.rm_rf(Radar.career_path)
      CareerData.reload!
    end
  end
end
