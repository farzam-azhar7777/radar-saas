require "test_helper"

# The distiller is usually right to skip, but it is not the one who has to live
# with the proposals. A skip has to be overrulable.
class KeepNoteTest < ActionDispatch::IntegrationTest
  test "a skipped note can be kept verbatim, and the page offers it" do
    fb = Feedback.create!(body: "Never name a repo in a proposal.", remembered: true,
                          outcome: Feedback::SKIPPED, outcome_note: "Already covered.")

    get lessons_path
    assert_select "form[action=?]", keep_note_path(fb)

    assert_difference "Lesson.count", 1 do
      post keep_note_path(fb)
    end

    lesson = Lesson.order(:id).last
    assert_equal "Never name a repo in a proposal.", lesson.body, "kept in his words, not reworded"
    assert fb.reload.learned?
    assert_equal lesson, fb.lesson
  end

  test "a note that already became a rule is not offered again" do
    lesson = Lesson.create!(body: "Name the product.")
    fb = Feedback.create!(body: "Name the product.", remembered: true,
                          outcome: Feedback::LEARNED, lesson: lesson)

    get lessons_path
    assert_select "form[action=?]", keep_note_path(fb), count: 0

    assert_no_difference("Lesson.count") { post keep_note_path(fb) }
    assert flash[:alert].present?
  end

  test "the page names the outcome of every tracked note" do
    Feedback.create!(body: "A skipped one.", remembered: true, outcome: Feedback::SKIPPED,
                     outcome_note: "Already covered by an existing rule.")

    get lessons_path

    assert_response :success
    assert_select "body", text: /Not kept/
    assert_select "body", text: /Already covered by an existing rule/
  end
end
