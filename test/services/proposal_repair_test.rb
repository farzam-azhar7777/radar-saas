require "test_helper"

# A failed check used to cost a second full generation: the whole spec, the
# whole job, the previous draft, and "do it better". That roughly doubled the
# wall clock of every proposal that tripped a single rule.
#
# Almost every failure is local, and the text is already written. Repair edits
# the offending parts and leaves the rest byte-for-byte alone.
class ProposalRepairTest < ActiveSupport::TestCase
  def section(label, role, body)
    ProposalSectioner::Section.new(label: label, role: role, body: body)
  end

  setup do
    @posting = JobPosting.create!(
      upwork_id: "rep-#{SecureRandom.hex(4)}", title: "Rails engineer",
      description: "Build an API." * 40, status: "matched", score: 80, published_at: 1.hour.ago
    )
    @shape = ProposalArchetype.new(@posting).call
    @sections = [
      section("Opening", "letter", "PadStats is a Rails 7 GraphQL API."),
      section("My relevant skills", "letter", "Rails 3 through 8.1 in production."),
      section("Related projects", "portfolio", "PadStats. See more at: http://padstats.com/")
    ]
  end

  def with_claude(reply)
    original = ClaudeRun.method(:call)
    ClaudeRun.define_singleton_method(:call) do |_prompt, **_opts|
      ClaudeRun::Result.new(text: reply, duration_ms: 500, meta: { "total_cost_usd" => 0.05 })
    end
    yield
  ensure
    ClaudeRun.define_singleton_method(:call, original)
  end

  test "only the returned parts change, the rest survive untouched" do
    reply = "```\n=== Related projects | portfolio ===\nPadStats, trimmed.\n```"

    result = with_claude(reply) do
      ProposalRepair.call(@posting, sections: @sections, failures: [ "Too long." ], shape: @shape)
    end

    assert_equal [ "Related projects" ], result.changed
    assert_equal "PadStats, trimmed.", result.sections.last.body
    assert_equal @sections.first.body, result.sections.first.body, "an untouched part must be identical"
    assert_equal @sections[1].body, result.sections[1].body
    assert_equal 3, result.sections.size, "repair must not drop or add parts"
  end

  test "a repaired part keeps its original label and role" do
    reply = "```\n=== opening | letter ===\nSurgePoint is a Rails 8 SaaS.\n```"

    result = with_claude(reply) do
      ProposalRepair.call(@posting, sections: @sections, failures: [ "Opener is too broad." ], shape: @shape)
    end

    assert_equal "Opening", result.sections.first.label, "matching is case-insensitive, the label is not rewritten"
    assert_equal "letter", result.sections.first.role
    assert_equal "SurgePoint is a Rails 8 SaaS.", result.sections.first.body
  end

  test "the prompt carries the failures and every part, and nothing else it does not need" do
    captured = nil
    original = ClaudeRun.method(:call)
    ClaudeRun.define_singleton_method(:call) do |prompt, **_o|
      captured = prompt
      ClaudeRun::Result.new(text: "```\n=== Opening | letter ===\nFixed.\n```", duration_ms: 1, meta: {})
    end

    ProposalRepair.call(@posting, sections: @sections, failures: [ "Contains banned phrases: seamless." ], shape: @shape)

    assert_includes captured, "Contains banned phrases: seamless."
    assert_includes captured, "My relevant skills"
    assert_includes captured, "This is an edit, not a rewrite"
    assert_not_includes captured, "Write a real Upwork proposal", "the full generation prompt is the thing being avoided"
  ensure
    ClaudeRun.define_singleton_method(:call, original)
  end

  test "an empty repair is an error rather than a silently emptied proposal" do
    with_claude("```\n\n```") do
      assert_raises(ProposalRepair::RepairError) do
        ProposalRepair.call(@posting, sections: @sections, failures: [ "Too long." ], shape: @shape)
      end
    end
  end

  test "nothing to repair is an error, not a no-op that looks like success" do
    assert_raises(ProposalRepair::RepairError) do
      ProposalRepair.call(@posting, sections: [], failures: [ "x" ], shape: @shape)
    end
    assert_raises(ProposalRepair::RepairError) do
      ProposalRepair.call(@posting, sections: @sections, failures: [], shape: @shape)
    end
  end
end
