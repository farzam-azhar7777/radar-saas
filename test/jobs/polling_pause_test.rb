require "test_helper"

# Pausing stops the automatic checks of Upwork and nothing else: the scheduler
# still reports itself alive, and Check now still works.
class PollingPauseTest < ActionDispatch::IntegrationTest
  setup do
    SavedSearch.create!(name: "Rails", terms: [ "rails" ], threshold: 70, hot_threshold: 80, active: true)
    Setting.clear(PollTickJob::NEXT_POLL_AT)
    @polled = 0
    @original = PollAllSearchesJob.instance_method(:perform)
    count = -> { @polled += 1 }
    PollAllSearchesJob.define_method(:perform) { |**| count.call }
  end

  teardown { PollAllSearchesJob.define_method(:perform, @original) }

  test "a paused install makes no automatic Upwork call, and still looks alive" do
    Setting.set(Setting::POLLING, "off")
    PollTickJob.perform_now

    assert_equal 0, @polled
    assert_not PollHealth.stalled?, "a pause is not a stall"
  end

  test "resuming checks again on the next tick" do
    Setting.set(Setting::POLLING, "off")
    post toggle_auto_polling_path
    assert Setting.auto_polling?

    PollTickJob.perform_now
    assert_equal 1, @polled
  end

  test "Check now still works while paused" do
    Setting.set(Setting::POLLING, "off")
    assert_enqueued_with(job: PollAllSearchesJob) { post poll_path }
  end

  test "the sidebar says it is paused and offers to resume" do
    Setting.set(Setting::POLLING, "off")
    get root_path
    assert_select "aside", text: /Paused/
    assert_select "form[action=?] button", toggle_auto_polling_path, text: "Resume"
  end

  # Chrome can allow alerts while macOS holds them back, and nothing in the
  # page can see the difference, so Settings offers a one-click test.
  test "settings offers a test alert with a place to explain the result" do
    get settings_path
    assert_select "button[data-action=?]", "alerts#test", text: "Send a test alert"
    assert_select "[data-alerts-target=testResult][hidden]"
  end
end
