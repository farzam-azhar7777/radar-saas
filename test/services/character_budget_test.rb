require "test_helper"

# Every letter measured on 24 September was inside its word budget. What blew
# the 5000-character limit was the letter, the answers and an unbudgeted
# projects block competing for the same space, and the model was never told the
# limit existed unless the post had questions buried in its description.
#
# The cost was time, not quality: the check caught it after a full generation
# and the cure was a second one. Median generation went from 180s to 566s.
class CharacterBudgetTest < ActiveSupport::TestCase
  def posting(questions: [], description: "Build a Rails API for a marketplace." * 20)
    JobPosting.create!(
      upwork_id: "char-#{SecureRandom.hex(4)}", title: "Rails backend engineer",
      description: description, screening_questions: questions,
      status: "matched", score: 80, published_at: 1.hour.ago
    )
  end

  def prompt_for(post)
    generator = ProposalGenerator.new(post)
    generator.send(:prompt, ProposalArchetype.new(post).call)
  end

  test "the character limit is stated on an ordinary post with no questions" do
    text = prompt_for(posting)

    assert_includes text, ProposalCheck::MAX_CHARS.to_s,
      "the model has to be told the limit it is being measured against"
    assert_match(/CHARACTER LIMIT/, text)
  end

  test "it is stated when the post has screening questions too" do
    assert_includes prompt_for(posting(questions: [ "How do you upgrade Rails?" ])),
      "CHARACTER LIMIT"
  end

  test "the projects block is given a budget, because it had none" do
    text = prompt_for(posting)

    assert_match(/at most #{ProposalGenerator::MAX_PROJECTS} projects/, text)
    assert_includes text, ProposalGenerator::PROJECT_WORDS.to_s
  end

  test "the target leaves headroom below the hard limit" do
    target = ProposalCheck::MAX_CHARS - ProposalGenerator::CHARACTER_HEADROOM

    assert_operator target, :<, ProposalCheck::MAX_CHARS
    assert_includes prompt_for(posting), target.to_s
  end

  test "the model is told to protect the letter and cut the projects first" do
    text = prompt_for(posting)

    assert_match(/first thing to cut/i, text)
    assert_match(/letter is what wins/i, text)
  end

  # An over-length failure used to say only "Cut it", so the rewrite shortened
  # the letter and left the block that caused the overrun intact.
  test "the over-length failure says how much to cut and from where" do
    archetype = { words: 100..200, has_questions: false, answer_words: nil, question_count: 0 }
    body = "word " * 1200 # comfortably over 5000 characters

    failure = ProposalCheck.call(body, archetype: archetype).fetch(:failures)
                           .find { |f| f.include?("over Upwork's") }

    assert failure, "expected an over-length failure"
    assert_match(/related projects block first/, failure)
    assert_match(/Keep the letter at its full length/, failure)
    assert_match(/\d+ over Upwork's #{ProposalCheck::MAX_CHARS} limit/, failure)
  end
end
