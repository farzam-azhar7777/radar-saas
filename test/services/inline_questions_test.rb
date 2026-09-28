require "test_helper"

# Feedback 2026-09-21: "when there are questions only in the job description and
# no separate screening questions... you still put them on top and hence I have
# to adjust the whole proposal structure myself... we loose the criteria where
# some one needs to see our initial good job winning lines... you mostly go over
# 5000 characters limit."
class InlineQuestionsTest < ActiveSupport::TestCase
  def posting(description, screening: [])
    JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails engineer", status: "matched",
                       score: 85, total_applicants: 3, description: description,
                       screening_questions: screening)
  end

  APPLY_LIST = <<~TEXT
    We need a senior Rails engineer for a long-running platform. #{"Context about the platform, the team and the roadmap. " * 12}

    ### To Apply

    Please submit:

    1. Your updated CV/resume
    2. Years of professional Ruby on Rails experience
    3. Availability/notice period
    4. Hourly rate or expected compensation
  TEXT

  test "an apply checklist in the description is found" do
    assert_equal 4, DescriptionQuestions.call(posting(APPLY_LIST)).size
    assert_equal "Your updated CV/resume", DescriptionQuestions.call(posting(APPLY_LIST)).first
  end

  test "Upwork's own screening questions take precedence and suppress it" do
    p = posting(APPLY_LIST, screening: [ "Why you?" ])
    assert_empty DescriptionQuestions.call(p), "formal questions get their own boxes; do not double up"
  end

  # One post used "please include" for deliverables (post-delivery support, API
  # fixtures) and only later asked the real questions. Taking the first cue made
  # scope bullets look like an application checklist.
  test "a deliverable list is not mistaken for the application ask" do
    text = <<~TEXT
      Please include post-delivery support for genuine problems.

      Please include saved, sanitized API response samples so parsers can be tested.

      - fixtures for amazon
      - fixtures for ebay

      Please answer the following rather than sending a generic proposal.

      1. Which official API would you use for each platform?
      2. How would you handle OAuth token refresh securely?
    TEXT
    questions = DescriptionQuestions.call(posting(text))
    assert_equal 2, questions.size
    assert_match "official API", questions.first
  end

  test "a post with no ask yields nothing" do
    assert_empty DescriptionQuestions.call(posting("Build us a Rails app. Long term, full time."))
  end

  test "a rhetorical opener is not a question to answer" do
    assert_empty DescriptionQuestions.call(posting("Struggling with slow queries? We need help."))
  end

  # --- what the engine then does with them ---

  test "the letter budget grows to hold the answers, since they live inside it" do
    plain = ProposalArchetype.new(posting("Build us a Rails app. " * 40)).call[:words]
    withq = ProposalArchetype.new(posting(APPLY_LIST)).call[:words]
    assert_operator withq.min, :>, plain.min, "the answers need room inside the letter"
    assert_operator withq.max, :<=, ProposalArchetype::MAX_LETTER_WORDS, "but not past the 5000 char ceiling"
  end

  test "opening with a numbered answer is rejected, because it costs the preview" do
    p = posting(APPLY_LIST)
    body = "1. My CV is attached.\n\n#{'word ' * 450}\nFarzam"
    failures = ProposalCheck.call(body, archetype: ProposalArchetype.new(p).call, posting: p)[:failures].join
    assert_match "opens with a numbered answer", failures
  end

  test "opening on the hook is accepted" do
    p = posting(APPLY_LIST)
    body = "Reviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. #{'word ' * 450}\nFarzam"
    failures = ProposalCheck.call(body, archetype: ProposalArchetype.new(p).call, posting: p)[:failures].join
    assert_no_match(/opens with a numbered answer/, failures)
  end

  test "a formal screening answer on top is still fine, it has its own box" do
    p = posting("Build a Rails app. " * 40, screening: [ "Why you?" ])
    body = "1. Because I have shipped this exact thing.\n\n-----\n\nQuick question: are you on Rails 7.1 or 8 already? #{'word ' * 195}\nFarzam"
    failures = ProposalCheck.call(body, archetype: ProposalArchetype.new(p).call, posting: p)[:failures].join
    assert_no_match(/opens with a numbered answer/, failures)
  end

  # --- Upwork's hard limit ---

  test "over 5000 characters is rejected outright" do
    p = posting(APPLY_LIST)
    body = "Reviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. #{'word ' * 1400}\nFarzam"
    failures = ProposalCheck.call(body, archetype: ProposalArchetype.new(p).call, posting: p)[:failures].join
    assert_match "over Upwork's 5000 limit", failures
  end

  test "bold Unicode is counted at two characters each, the way the browser does" do
    result = ProposalCheck.call("\u{1D5D8}\u{1D605}", archetype: { words: 1..10 }, posting: nil)
    assert_equal 4, result[:characters]
  end
end
