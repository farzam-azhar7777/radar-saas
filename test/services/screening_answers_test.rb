require "test_helper"

# Feedback on job 6892: "All the weight got into answering the questions and
# proposal itself lost its worth i.e. became too short and wasn't attractive
# anymore" and "responses to the questions are coming toooo long... not in
# machine way like its been doing."
#
# The shipped draft was 464 words of bulleted runbook above a 131-word letter.
class ScreeningAnswersTest < ActiveSupport::TestCase
  def posting(questions:, bids: 5, spend: 0)
    JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Expert Rails and Postgres Upgrade",
                       description: "x" * 800, status: "matched", score: 85,
                       total_applicants: bids, client_total_spent: spend,
                       screening_questions: questions)
  end

  def shape_for(p) = ProposalArchetype.new(p).call

  def check(body, p) = ProposalCheck.call(body, archetype: shape_for(p), posting: p)

  # --- the letter must stop being the stub ---

  test "screening questions no longer shrink the letter" do
    with = shape_for(posting(questions: [ "How do you do Rails upgrades?" ]))
    without = shape_for(posting(questions: []))
    assert_equal without[:words], with[:words], "the letter is the pitch and keeps its budget"
  end

  test "a stub letter under questions is rejected" do
    p = posting(questions: [ "How do you do Rails upgrades?" ])
    body = "1. #{'word ' * 70}\n\n-----\n\nReviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. #{'word ' * 80}\nFarzam"
    assert_includes check(body, p)[:failures].join, "under the 320 to 460 budget"
  end

  # --- the answers must stop being a runbook ---

  test "several questions in one Upwork field are counted separately" do
    p = posting(questions: [ "What is your approach to Rails upgrades.\nWhat is your approach to Postgres upgrades.\nCan you showcase past work." ])
    assert_equal 3, ProposalArchetype.new(p).question_count
  end

  test "a single question is one answer" do
    assert_equal 1, ProposalArchetype.new(posting(questions: [ "How do you do Rails upgrades?" ])).question_count
  end

  test "answers have a budget at all, scaled to how many there are" do
    one = shape_for(posting(questions: [ "One?" ]))[:answer_words]
    three = shape_for(posting(questions: [ "One?\nTwo?\nThree?" ]))[:answer_words]
    assert_equal 45..90, one
    assert_equal 135..270, three
  end

  # A note since 2026-09-25: he trims an answer in twenty seconds, and a
  # repair to do it cost minutes.
  test "overlong answers are flagged without blaming the letter" do
    p = posting(questions: [ "How do you do Rails upgrades?" ])
    body = "1. #{'word ' * 300}\n\n-----\n\nReviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. #{'word ' * 340}\nFarzam"
    result = check(body, p)
    note = result[:notes].find { |f| f.include?("screening answers") }
    assert_match "target 45-90", note
    assert_empty result[:notes].select { |n| n.include?("The letter is") }, "the letter is inside its range"
  end

  test "a wall of bullets is flagged as machine-written" do
    p = posting(questions: [ "How do you do Rails upgrades?" ])
    bullets = (1..9).map { |i| "- step #{i} that is done carefully and thoroughly" }.join("\n")
    body = "1. Here is how.\n#{bullets}\n\n-----\n\nReviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. #{'word ' * 340}\nFarzam"
    assert_includes check(body, p)[:notes].join, "read as a pasted runbook"
  end

  test "a couple of bullets per answer is still fine" do
    p = posting(questions: [ "How do you do Rails upgrades?" ])
    body = "1. One minor at a time, dual-booted in CI. #{'word ' * 50}\n- Bounce Rental went 4 to 7.1 this way\n- pandOS runs 8.1 today\n\n-----\n\nReviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. #{'word ' * 340}\nFarzam"
    assert_not_includes check(body, p)[:notes].join, "runbook"
  end

  test "a well-shaped answer block and letter passes" do
    p = posting(questions: [ "How do you do Rails upgrades?" ])
    body = "1. #{'word ' * 70}\n\n-----\n\nReviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. #{'word ' * 340}\nFarzam"
    result = check(body, p)
    assert_empty result[:failures]
    # 195 filler + 10-word opener + "Farzam"
    assert_equal 355, result[:letter_words]
  end

  test "a post with no questions is unaffected" do
    p = posting(questions: [])
    assert_nil shape_for(p)[:answer_words]
    assert_empty check("Reviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. #{'word ' * 340}\nFarzam", p)[:failures]
  end
end
