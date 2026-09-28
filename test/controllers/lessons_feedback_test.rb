require "test_helper"

# Feedback that is not about any one proposal. Before this, the only way to
# teach Radar anything was to rewrite a proposal, which meant paying for a
# generation in order to say "stop using the word platform".
class LessonsFeedbackTest < ActionDispatch::IntegrationTest
  test "the page offers a box that does not touch any proposal" do
    get lessons_path

    assert_response :success
    assert_select "form[action=?]", teach_lessons_path do
      assert_select "button[name=mode][value=verbatim]"
      assert_select "button[name=mode][value=distill]"
      assert_select "select[name=saved_search_id]"
    end
  end

  test "saving it verbatim creates the rule immediately and spends nothing" do
    assert_difference [ "Lesson.count", "Feedback.count" ], 1 do
      assert_no_enqueued_jobs(only: DistillLessonJob) do
        post teach_lessons_path, params: { body: "Lead with a live product, never a stack list.", mode: "verbatim" }
      end
    end

    lesson = Lesson.order(:id).last
    assert_equal "Lead with a live product, never a stack list.", lesson.body
    assert_nil lesson.saved_search_id, "no scope chosen means every proposal"
    assert lesson.active?
  end

  test "letting Radar word it records the note and distils in the background" do
    assert_difference "Feedback.count", 1 do
      assert_no_difference "Lesson.count" do
        assert_enqueued_with(job: DistillLessonJob) do
          post teach_lessons_path, params: { body: "The openings all sound the same.", mode: "distill" }
        end
      end
    end
  end

  test "a rule can be scoped to one search" do
    search = SavedSearch.create!(name: "Rails #{SecureRandom.hex(3)}", terms: [ "rails" ])

    post teach_lessons_path, params: { body: "Name the Rails version.", mode: "verbatim", saved_search_id: search.id }

    assert_equal search.id, Lesson.order(:id).last.saved_search_id
  end

  # Distilling costs money. Anything that posts without saying which it wants
  # must not quietly spend it.
  test "a missing mode takes the free path" do
    assert_no_enqueued_jobs(only: DistillLessonJob) do
      post teach_lessons_path, params: { body: "Name the Rails version every time." }
    end
    assert_equal "Name the Rails version every time.", Lesson.order(:id).last.body
  end

  test "an empty note saves nothing" do
    assert_no_difference [ "Lesson.count", "Feedback.count" ] do
      post teach_lessons_path, params: { body: "  " }
    end
    assert flash[:alert].present?
  end

  # A rule is injected into the prompt verbatim, so a dash in the rule teaches
  # the dash back into every proposal.
  test "an em dash typed into the box is normalised away" do
    post teach_lessons_path, params: { body: "Keep it short — two sentences.", mode: "verbatim" }

    assert_equal "Keep it short - two sentences.", Lesson.order(:id).last.body
  end

  test "a hand-written rule reaches the next proposal's prompt" do
    post teach_lessons_path, params: { body: "Always name the Postgres version.", mode: "verbatim" }

    assert_includes Lesson.prompt_block.to_s, "Always name the Postgres version."
  end
end
