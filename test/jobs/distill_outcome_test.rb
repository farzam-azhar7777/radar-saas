require "test_helper"

# A note he writes can become a rule, be judged already covered, or fail. All
# three used to look identical on the page: a note that produced nothing. He
# wrote one on 24 September, it was correctly skipped as a duplicate, and there
# was no way for him to tell that from the feature being broken.
class DistillOutcomeTest < ActiveSupport::TestCase
  setup { @feedback = Feedback.create!(body: "Stop using repo names in proposals.", remembered: true) }

  def with_distiller(reply)
    original = DistillLessonJob.instance_method(:ask)
    DistillLessonJob.define_method(:ask) { |_| reply }
    yield
  ensure
    DistillLessonJob.define_method(:ask, original)
  end

  test "a distilled note records the rule it became" do
    with_distiller(%({"skip": false, "scope": "global", "lesson": "Name the product, not the repo."})) do
      assert_difference("Lesson.count", 1) { DistillLessonJob.new.perform(@feedback) }
    end

    @feedback.reload
    assert @feedback.learned?
    assert_equal "Name the product, not the repo.", @feedback.lesson.body
    assert_equal "Became a rule", @feedback.status_label
  end

  test "a skip records why, so a correct decision is not mistaken for a failure" do
    reply = %({"skip": true, "reason": "Already covered by the rule about naming the real product."})

    with_distiller(reply) do
      assert_no_difference("Lesson.count") { DistillLessonJob.new.perform(@feedback) }
    end

    @feedback.reload
    assert @feedback.skipped?
    assert_match(/Already covered/, @feedback.outcome_note)
    assert_equal "Not kept", @feedback.status_label
  end

  test "a skip with no reason still says something rather than nothing" do
    with_distiller(%({"skip": true})) { DistillLessonJob.new.perform(@feedback) }

    assert @feedback.reload.outcome_note.present?
  end

  test "an unreadable answer is recorded as a failure, not a silent skip" do
    with_distiller("I'm afraid I can't do that") { DistillLessonJob.new.perform(@feedback) }

    @feedback.reload
    assert @feedback.failed?
    assert_equal "Could not be read", @feedback.status_label
  end

  test "an empty answer is a failure too" do
    with_distiller(nil) { DistillLessonJob.new.perform(@feedback) }

    assert @feedback.reload.failed?
  end

  test "a note left pending by a dead worker stops claiming to be working" do
    @feedback.update_columns(outcome: Feedback::PENDING, created_at: 2.hours.ago)

    assert_not @feedback.pending?
    assert @feedback.stalled?
    assert_equal "Gave up", @feedback.status_label
  end
end
