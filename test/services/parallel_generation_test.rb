require "test_helper"

# Writing the parts concurrently is only safe because no writer is blind: they
# all receive the same plan, which decides the argument and hands each piece of
# evidence to exactly one part. These tests cover the seams where that breaks
# down, and the fallbacks for when a phase fails outright.
#
# Nothing here shells out to claude. A test that costs real money and three
# minutes is a test nobody runs.
class ParallelGenerationTest < ActiveSupport::TestCase
  PLAN = {
    "angle" => "He has shipped this exact system.",
    "opening" => { "project" => "SurgePoint", "proof" => "842 of 863 commits", "hook" => "Here is how I fit:" },
    "parts" => [
      { "label" => "Opening", "role" => "letter", "group" => "open", "words" => 45, "brief" => "lead with SurgePoint" },
      { "label" => "How I fit", "role" => "letter", "group" => "open", "words" => 60, "brief" => "the list" },
      { "label" => "My relevant skills", "role" => "letter", "group" => "argue", "words" => 150, "brief" => "map requirements" },
      { "label" => "Ready to start", "role" => "letter", "group" => "close", "words" => 40, "brief" => "next step" },
      { "label" => "Related projects", "role" => "portfolio", "group" => "portfolio", "words" => 90, "brief" => "three projects" }
    ]
  }.freeze

  setup do
    @posting = JobPosting.create!(
      upwork_id: "par-#{SecureRandom.hex(4)}", title: "Rails backend engineer",
      description: "Build a marketplace API on Rails." * 20,
      status: "matched", score: 84, published_at: 1.hour.ago
    )
    @shape = ProposalArchetype.new(@posting).call
  end

  # Each writer is handed the labels it must emit, so a canned reply that
  # echoes them back is exactly what a real writer produces.
  def reply_for(prompt)
    labels = prompt.scan(/^=== (.+?) \| (\w+) ===$/)
    body = labels.map { |label, role| "=== #{label} | #{role} ===\n#{label} body text here." }.join("\n\n")
    "```\n#{body}\n```"
  end

  def with_claude(handler)
    original = ClaudeRun.method(:call)
    ClaudeRun.define_singleton_method(:call) do |prompt, **opts|
      ClaudeRun::Result.new(text: handler.call(prompt, opts), duration_ms: 1000,
                            meta: { "total_cost_usd" => 0.1, "num_turns" => 2, "duration_api_ms" => 900 })
    end
    yield
  ensure
    ClaudeRun.define_singleton_method(:call, original)
  end

  # --- the plan ------------------------------------------------------------

  test "the plan is parsed out of a fenced block" do
    with_claude(->(_p, _o) { "here you go\n```json\n#{PLAN.to_json}\n```" }) do
      plan = ProposalPlan.call(@posting, shape: @shape)

      assert_equal 5, plan.data["parts"].size
      assert_equal "SurgePoint", plan.data.dig("opening", "project")
    end
  end

  test "a plan with no parts is an error, not an empty proposal" do
    with_claude(->(_p, _o) { "```json\n{\"parts\": []}\n```" }) do
      assert_raises(ProposalPlan::PlanError) { ProposalPlan.call(@posting, shape: @shape) }
    end
  end

  test "a plan that is not JSON is an error" do
    with_claude(->(_p, _o) { "I could not do that" }) do
      assert_raises(ProposalPlan::PlanError) { ProposalPlan.call(@posting, shape: @shape) }
    end
  end

  test "the plan prompt carries the questions, budgets and learned rules" do
    Lesson.create!(body: "Name the real product, never the repo.")
    captured = nil
    @posting.update!(screening_questions: [ "How do you handle migrations?" ])

    with_claude(->(p, _o) { captured = p; "```json\n#{PLAN.to_json}\n```" }) do
      ProposalPlan.call(@posting, shape: ProposalArchetype.new(@posting).call)
    end

    assert_includes captured, "How do you handle migrations?"
    assert_includes captured, "Name the real product, never the repo."
    assert_includes captured, ProposalCheck::MAX_CHARS.to_s
  end

  # A post with no screening questions that gets an "answer" part assembles
  # with a ----- separator above it, ProposalParts reads that as the answer
  # block, and a 500-word letter measures as 74 words. The checks then fail on
  # a number that was never real.
  test "an answer part on a post with no questions is relabelled, not kept" do
    plan = PLAN.merge("parts" => PLAN["parts"] + [
      { "label" => "Answer: React in production", "role" => "answer", "group" => "answers", "words" => 70, "brief" => "x" }
    ])

    with_claude(->(_p, _o) { "```json\n#{plan.to_json}\n```" }) do
      result = ProposalPlan.call(@posting, shape: @shape)

      assert_equal 0, result.data["parts"].count { |p| p["role"] == "answer" }
      assert_equal 6, result.data["parts"].size, "the content is kept, only the role changes"
    end
  end

  test "more answer parts than questions is trimmed back to the questions asked" do
    @posting.update!(screening_questions: [ "One question?" ])
    plan = PLAN.merge("parts" => [
      { "label" => "A1", "role" => "answer", "group" => "answers", "words" => 70, "brief" => "x" },
      { "label" => "A2", "role" => "answer", "group" => "answers", "words" => 70, "brief" => "x" },
      { "label" => "Opening", "role" => "letter", "group" => "open", "words" => 45, "brief" => "x" }
    ])

    with_claude(->(_p, _o) { "```json\n#{plan.to_json}\n```" }) do
      result = ProposalPlan.call(@posting, shape: ProposalArchetype.new(@posting).call)

      assert_equal 1, result.data["parts"].count { |p| p["role"] == "answer" }
    end
  end

  test "an unknown role becomes letter rather than breaking the assembler" do
    plan = PLAN.merge("parts" => [ PLAN["parts"].first.merge("role" => "preamble") ])

    with_claude(->(_p, _o) { "```json\n#{plan.to_json}\n```" }) do
      assert_equal "letter", ProposalPlan.call(@posting, shape: @shape).data["parts"].first["role"]
    end
  end

  # --- the writers ---------------------------------------------------------

  test "parts are written in groups, one call per group" do
    prompts = []

    result = with_claude(->(p, _o) { prompts << p; reply_for(p) }) do
      ParallelProposalWriter.call(@posting, plan: PLAN, shape: @shape)
    end

    assert_equal 4, prompts.size, "open, argue, close and portfolio is four writers, not five parts"
    assert_equal 5, result.sections.size
    assert_equal [ "Opening", "How I fit", "My relevant skills", "Ready to start", "Related projects" ],
                 result.sections.map(&:label)
  end

  test "parts come back in reading order however the threads finish" do
    result = with_claude(->(p, _o) { sleep(p.include?("open") ? 0.05 : 0); reply_for(p) }) do
      ParallelProposalWriter.call(@posting, plan: PLAN, shape: @shape)
    end

    assert_equal "Opening", result.sections.first.label
    assert_equal "portfolio", result.sections.last.role
  end

  test "every writer is given the whole plan, so none of them is blind" do
    prompts = []

    with_claude(->(p, _o) { prompts << p; reply_for(p) }) do
      ParallelProposalWriter.call(@posting, plan: PLAN, shape: @shape)
    end

    prompts.each do |p|
      assert_includes p, "842 of 863 commits", "a writer that cannot see the plan will contradict the others"
      assert_includes p, "Here is how I fit:"
    end
  end

  test "one writer failing does not lose the other three" do
    result = with_claude(->(p, _o) { raise ClaudeRun::Error, "timed out" if p.include?("(argue)"); reply_for(p) }) do
      ParallelProposalWriter.call(@posting, plan: PLAN, shape: @shape)
    end

    assert_equal 4, result.sections.size, "argue held one part, so four survive"
    assert_not_includes result.sections.map(&:label), "My relevant skills"
    assert result.meta["writer_errors"].present?, "a lost part has to be visible in the metadata"
  end

  test "cost adds up across writers but wall time is the slowest one" do
    result = with_claude(->(p, _o) { reply_for(p) }) do
      ParallelProposalWriter.call(@posting, plan: PLAN, shape: @shape)
    end

    assert_in_delta 0.4, result.meta["total_cost_usd"], 0.001, "four writers at 0.1 each"
    assert_equal 900, result.meta["duration_api_ms"], "the longest leg, not the sum"
  end

  test "an unknown group still gets written rather than dropped" do
    plan = PLAN.merge("parts" => [ PLAN["parts"].first.merge("group" => "nonsense") ])

    result = with_claude(->(p, _o) { reply_for(p) }) do
      ParallelProposalWriter.call(@posting, plan: plan, shape: @shape)
    end

    assert_equal 1, result.sections.size
  end

  # --- the generator around them -------------------------------------------

  # Parallel is off by default until it is proven faster, so the test that
  # covers it has to turn it on.
  test "the generator assembles a body that matches its parts" do
    ENV["RADAR_PARALLEL_GENERATION"] = "1"

    result = with_claude(lambda { |p, _o|
      next "```json\n#{PLAN.to_json}\n```" if p.include?("You are planning")

      reply_for(p)
    }) { ProposalGenerator.call(@posting) }

    assert_equal "parallel", result.meta["mode"]
    assert_equal 5, result.sections.size
    assert_equal ProposalAssembler.call(result.sections), result.body
  ensure
    ENV.delete("RADAR_PARALLEL_GENERATION")
  end

  # A slow proposal is a nuisance. No proposal is a lost job.
  test "a failed plan falls back to writing the whole thing in one pass" do
    ENV["RADAR_PARALLEL_GENERATION"] = "1"
    result = with_claude(lambda { |p, _o|
      raise ClaudeRun::Error, "plan timed out" if p.include?("You are planning")

      "```\n=== Opening | letter ===\nA whole proposal written in one pass.\n```"
    }) { ProposalGenerator.call(@posting) }

    assert_equal "serial", result.meta["mode"]
    assert_includes result.body, "written in one pass"
  ensure
    ENV.delete("RADAR_PARALLEL_GENERATION")
  end

  test "writers all failing falls back too, rather than saving an empty proposal" do
    ENV["RADAR_PARALLEL_GENERATION"] = "1"
    result = with_claude(lambda { |p, _o|
      next "```json\n#{PLAN.to_json}\n```" if p.include?("You are planning")
      raise ClaudeRun::Error, "writer died" if p.include?("You are writing PART")

      "```\n=== Opening | letter ===\nFallback body.\n```"
    }) { ProposalGenerator.call(@posting) }

    assert_equal "serial", result.meta["mode"]
    assert_includes result.body, "Fallback body."
  ensure
    ENV.delete("RADAR_PARALLEL_GENERATION")
  end

  test "the parallel path can be switched off entirely" do
    ENV["RADAR_PARALLEL_GENERATION"] = "0"

    result = with_claude(->(_p, _o) { "```\n=== Opening | letter ===\nSerial body.\n```" }) do
      ProposalGenerator.call(@posting)
    end

    assert_equal "serial", result.meta["mode"]
  ensure
    ENV.delete("RADAR_PARALLEL_GENERATION")
  end
end
