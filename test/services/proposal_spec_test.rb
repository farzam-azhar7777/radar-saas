require "test_helper"

class ProposalSpecTest < ActiveSupport::TestCase
  test "every placeholder is filled" do
    text = ProposalSpec.render
    assert_no_match(/\{\{\w+\}\}/, text)
  end

  test "someone else's spec carries none of Farzam's facts" do
    ada = Profile.new(full_name: "Ada Lovelace", title: "Rails Developer")
    text = ProposalSpec.render(ada)

    %w[Farzam Surge 842 𝑭𝒂𝒓𝒛𝒂𝒎 acts_as_tenant].each { |t| assert_not_includes text, t }
    assert_includes text, "sound like Ada talking"
    assert_includes text, "𝑨𝒅𝒂 𝑳𝒐𝒗𝒆𝒍𝒂𝒄𝒆"
  end

  test "without an opening of their own, the example is brackets, never an invented product" do
    text = ProposalSpec.render(Profile.new(full_name: "Ada Lovelace"))
    assert_includes text, "[Live product name] is the closest thing to [what they are building]"
    assert_includes ProposalSpec.opening_model(Profile.new(full_name: "Ada")), "filling every bracket"
  end

  test "their own winning opening becomes the example" do
    ada = Profile.new(full_name: "Ada Lovelace", winning_opening: "Ledgerline is my billing SaaS, 610 of 640 commits mine.",
                      winning_opening_context: "for a billing role")
    text = ProposalSpec.render(ada)

    assert_includes text, "Real example, the one Ada actually sent for a billing role:"
    assert_includes text.gsub(/\n> /, " "), "Ledgerline is my billing SaaS, 610 of 640 commits mine."
  end

  test "standing is claimed only when they gave one" do
    assert_includes ProposalSpec.render(Profile.new(full_name: "Ada", credentials_line: "Top Rated")), "made Ada Top Rated"
    assert_includes ProposalSpec.render(Profile.new(full_name: "Ada")), "gets a proposal opened and answered"
  end

  test "skill examples are their own tools" do
    assert_includes ProposalSpec.skill_examples, "Sidekiq"
  end

  test "the planner still receives the structure section after its heading changed" do
    plan = ProposalPlan.new(JobPosting.new(title: "t", description: "d"), shape: { signals: [], words: 100..200, key: "B", name: "x", inline_questions: [] })
    assert_includes plan.send(:spec), "## The structure that wins the work"
  end

  test "the rewriter still receives the voice section" do
    assert_includes ProposalSpec.section("Voice"), "Hyphens. Never em dashes"
  end
end
