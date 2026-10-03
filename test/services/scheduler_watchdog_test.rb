require "test_helper"

# 2026-10-01: a sleep left the scheduler hung in its own shutdown, alive and
# unregistered, and polling stopped for 39 hours. The supervisor only replaces
# children that exit, so the watchdog makes the hung one exit.
class SchedulerWatchdogTest < ActiveSupport::TestCase
  SUPERVISOR = 89590

  PS = <<~PS
    89590 89564 solid-queue-fork-supervisor(1.7.0): supervising 84680, 57682
    84680 89590 solid-queue-scheduler(1.7.0): scheduling poll_tick
    57682 89590 solid-queue-worker(1.7.0): waiting for jobs in generation
    70001 31061 solid-queue-scheduler(1.7.0): scheduling something_else
  PS

  # The test database has no solid_queue tables; registration is the input here.
  def check(registered:, seen:, now:)
    killed = []
    SchedulerWatchdog.check!(supervisor_pid: SUPERVISOR, seen: seen, now: now, ps_output: PS,
                             find_unregistered: ->(pids) { pids - registered },
                             killer: ->(pid) { killed << pid; pid })
    killed
  end

  test "finds only its own supervisor's scheduler" do
    assert_equal [ 84680 ], SchedulerWatchdog.scheduler_children(SUPERVISOR, PS)
  end

  test "a registered scheduler is left alone" do
    seen = {}
    assert_empty check(registered: [ 84680 ], seen: seen, now: Time.current)
    assert_empty seen
  end

  # A scheduler that is shutting down normally exits within seconds.
  test "an unregistered scheduler gets a grace period first" do
    seen = {}
    assert_empty check(registered: [], seen: seen, now: Time.current)
    assert seen.key?(84680)
  end

  test "still unregistered after the grace, it is killed" do
    seen = {}
    start = Time.current
    check(registered: [], seen: seen, now: start)
    assert_equal [ 84680 ], check(registered: [], seen: seen, now: start + SchedulerWatchdog::GRACE)
    assert_empty seen, "forgotten once killed, so its replacement starts clean"
  end

  test "a scheduler that registers again is forgiven" do
    seen = {}
    start = Time.current
    check(registered: [], seen: seen, now: start)
    assert_empty check(registered: [ 84680 ], seen: seen, now: start + SchedulerWatchdog::GRACE)
    assert_empty seen
  end

  test "another app's scheduler is never touched" do
    seen = {}
    start = Time.current
    check(registered: [], seen: seen, now: start)
    killed = check(registered: [], seen: seen, now: start + 10.minutes)
    assert_not_includes killed, 70001
  end
end
