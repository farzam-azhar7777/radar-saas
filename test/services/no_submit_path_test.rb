require "test_helper"

# Radar must never be able to submit a proposal, spend a Connect, or send a
# message on a freelancer's behalf. Upwork bans auto-bidders permanently, and
# the whole product depends on that line being structural rather than a promise
# someone can talk themselves out of later.
#
# These tests fail if a future change moves the line. That is the point: this
# file is the mechanism, not documentation of one.
class NoSubmitPathTest < ActiveSupport::TestCase
  APP = Rails.root.join("app")
  LIB = Rails.root.join("lib")

  def source_files
    Dir[APP.join("**", "*.rb")] + Dir[LIB.join("**", "*.rb")]
  end

  # The drafting engine runs a language model as a subprocess. Giving it a write
  # tool, a shell, or network access would hand it the ability to act on the
  # freelancer's account. Read-only is the guarantee.
  test "every language model subprocess is restricted to read-only tools" do
    granted = ClaudeRun::ALLOWED_TOOLS.split(",").map(&:strip).sort

    assert_equal %w[Glob Grep Read], granted,
      "a model subprocess was granted #{granted.inspect}; only read tools are permitted"
  end

  # Every call now goes through one runner, so there is exactly one place the
  # restriction can be loosened and exactly one place to guard.
  test "nothing spawns claude except the shared runner" do
    spawners = source_files.select { |f| File.read(f).include?("Radar.claude_bin") }
                           .map { |f| Pathname(f).relative_path_from(Rails.root).to_s }

    assert_equal [ "app/services/claude_run.rb" ], spawners
  end

  # DistillLessonJob shells out too, and was easy to forget.
  test "every claude invocation in the codebase passes allowedTools" do
    callers = source_files.select { |f| File.read(f).include?("claude_bin") }
    assert callers.any?, "expected to find the subprocess callers"

    callers.each do |file|
      body = File.read(file)
      assert_includes body, "--allowedTools",
        "#{Pathname(file).relative_path_from(Rails.root)} runs claude without restricting its tools"
      assert_match(/Read,\s*Glob,\s*Grep/, body,
        "#{Pathname(file).relative_path_from(Rails.root)} grants tools beyond Read, Glob and Grep")
    end
  end

  # Upwork's public GraphQL API exposes no proposal-submit mutation. If one ever
  # appears, this test is what stops someone quietly wiring it up.
  test "no GraphQL mutation is sent anywhere in the codebase" do
    offenders = source_files.select do |file|
      File.read(file).match?(/^\s*mutation\s|\bmutation\s*\{|"mutation/)
    end

    assert_empty offenders.map { |f| Pathname(f).relative_path_from(Rails.root).to_s },
      "Radar must only ever read from Upwork. A mutation means it can act on an account."
  end

  # Applying, messaging and spending Connects are the three things that would
  # turn this from an assistant into an auto-bidder.
  FORBIDDEN = {
    "submitProposal" => "submitting a proposal",
    "createProposal" => "submitting a proposal",
    "applyToJob"     => "applying to a job",
    "sendMessage"    => "messaging a client",
    "createRoom"     => "messaging a client",
    "spendConnects"  => "spending Connects"
  }.freeze

  test "no call that acts on a user's Upwork account exists" do
    source_files.each do |file|
      body = File.read(file)
      FORBIDDEN.each do |token, what|
        assert_not body.include?(token),
          "#{Pathname(file).relative_path_from(Rails.root)} references #{token}, which would mean #{what}"
      end
    end
  end

  # Radar reaches Upwork through the official API only. A browser driver or an
  # HTML fetch of upwork.com would be scraping, which the Terms prohibit and
  # which is how the auto-bidders operate.
  test "Upwork is reached only through the official API host" do
    hosts = source_files.flat_map { |f| File.read(f).scan(%r{https?://[a-z0-9.\-]*upwork\.com}i) }.uniq

    permitted = %w[https://api.upwork.com https://www.upwork.com]
    unexpected = hosts.reject { |h| permitted.include?(h.downcase) }

    assert_empty unexpected, "unexpected Upwork host in source: #{unexpected.inspect}"
  end

  test "no browser automation driver is a dependency" do
    lockfile = File.read(Rails.root.join("Gemfile.lock"))

    %w[selenium-webdriver watir ferrum cuprite playwright puppeteer mechanize].each do |gem|
      assert_no_match(/^\s{4}#{Regexp.escape(gem)}\s/, lockfile,
        "#{gem} is a browser automation driver; Radar must not be able to drive a logged-in session")
    end
  end
end
