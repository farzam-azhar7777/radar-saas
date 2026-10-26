require "test_helper"

class ScreeningQuestionsPageTest < ActionDispatch::IntegrationTest
  QUESTIONS = [ "Describe a RAG feature you built.", "How do you isolate tenants?" ].freeze

  setup do
    search = SavedSearch.create!(name: "AI", terms: [ "rag" ], threshold: 70, hot_threshold: 80)
    @posting = JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "AI platform", status: "matched", score: 90,
                                  saved_search: search, screening_questions: QUESTIONS)
    proposal = @posting.proposals.create!(version: 1, body: "x", generated_at: Time.current)
    [ [ "RAG grounding", "answer", "Mandala keeps answers grounded." ],
      [ "Tenants", "answer", "Database per tenant on Einlagen." ],
      [ "Opening", "letter", "Mandala is the closest thing." ],
      [ "Sign-off", "letter", "Regards,\nSohair A." ] ].each_with_index do |(label, role, body), i|
      proposal.sections.create!(label: label, role: role, body: body, position: i)
    end
  end

  test "each answer sits under the question it answers, with its own copy button" do
    get job_posting_path(@posting)

    assert_select "#answer-1 ~ div", text: /Question 1 of 2\s*#{Regexp.escape(QUESTIONS[0])}/
    assert_select "#answer-2 ~ div", text: /Question 2 of 2\s*#{Regexp.escape(QUESTIONS[1])}/
    assert_select "button", text: "Copy answer 1"
    assert_select "button", text: "Copy answer 2"
    assert_select "[data-clipboard-key-value=answer-2]"
  end

  test "the page lists every box to fill on Upwork, cover letter first" do
    get job_posting_path(@posting)

    assert_select "[data-paste-target=step]", 3
    assert_equal %w[letter answer-1 answer-2], css_select("[data-paste-target=step]").map { |s| s["data-key"] }
    assert_operator response.body.index('id="cover-letter"'), :<, response.body.index('id="screening"')
  end

  test "the questions lead the left column and link to their answers" do
    get job_posting_path(@posting)

    assert_select "a[href='#questions']", text: "2 screening questions"
    assert_select "#questions a[href='#answer-2']", text: "See answer"
    assert_operator response.body.index('id="questions"'), :<, response.body.index(">The post<")
  end

  test "a post without screening questions shows no checklist" do
    @posting.update!(screening_questions: [])
    @posting.latest_proposal.sections.where(role: "answer").destroy_all

    get job_posting_path(@posting)
    assert_select "[data-paste-target=step]", 0
    assert_select "#questions", 0
  end
end
