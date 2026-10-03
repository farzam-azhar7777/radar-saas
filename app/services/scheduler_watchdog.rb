# Polling died for 39 hours (2026-10-01 19:27 UTC onwards) with every process up.
#
# The laptop sleeps, solid_queue's supervisor prunes the scheduler's registration
# for missed heartbeats, and the scheduler, finding itself unregistered, starts
# shutting down: it cancels its recurring timers and then hangs in shutdown. The
# process stays alive, so the supervisor, which only replaces children that exit,
# never starts a new one. PollHealth's page-load revival kept polls trickling in
# only while a Radar tab was open.
#
# This runs inside the supervisor (config/initializers/solid_queue_watchdog.rb).
# A scheduler child that stays unregistered past GRACE is killed, and the
# supervisor forks a fresh, registered one within a second. It also revives
# polling directly, so a stall recovers with no browser open at all.
module SchedulerWatchdog
  module_function

  CHECK_EVERY = 60 # seconds

  # A normal shutdown finishes in seconds and a new fork registers as it boots,
  # so a scheduler still unregistered after this is the hung one.
  GRACE = 90.seconds

  # PIDs of the given supervisor's scheduler children, from the process table.
  # The procline is how solid_queue names its forks: "solid-queue-scheduler(...)".
  def scheduler_children(supervisor_pid, ps_output = nil)
    ps_output ||= IO.popen([ "ps", "-A", "-o", "pid=,ppid=,command=" ], &:read)
    ps_output.each_line.filter_map do |line|
      pid, ppid, command = line.strip.split(/\s+/, 3)
      pid.to_i if ppid.to_i == supervisor_pid && command.to_s.start_with?("solid-queue-scheduler")
    end
  end

  def unregistered(pids)
    return [] if pids.empty?

    pids - SolidQueue::Process.where(kind: "Scheduler", pid: pids).pluck(:pid)
  end

  # `seen` remembers when each suspect was first noticed, across checks.
  # Returns the PIDs it killed. The lookup and the kill are injectable for tests.
  def check!(supervisor_pid:, seen:, now: Time.current, ps_output: nil,
             find_unregistered: method(:unregistered), killer: method(:kill))
    suspects = find_unregistered.call(scheduler_children(supervisor_pid, ps_output))
    seen.select! { |pid, _| suspects.include?(pid) }

    suspects.filter_map do |pid|
      first_seen = (seen[pid] ||= now)
      next if now - first_seen < GRACE

      Rails.logger.warn("[SchedulerWatchdog] scheduler #{pid} unregistered since " \
                        "#{first_seen.iso8601}; killing it so the supervisor starts a fresh one")
      seen.delete(pid)
      killer.call(pid)
    end
  end

  def kill(pid)
    ::Process.kill(:KILL, pid)
    pid
  rescue Errno::ESRCH
    nil
  end

  def start(supervisor_pid = ::Process.pid)
    seen = {}
    Rails.logger.info("[SchedulerWatchdog] watching the schedulers of supervisor #{supervisor_pid}")
    Thread.new do
      Thread.current.name = "scheduler-watchdog"
      loop do
        sleep CHECK_EVERY
        Rails.application.reloader.wrap do
          check!(supervisor_pid: supervisor_pid, seen: seen)
          PollHealth.revive! if Onboarding.complete?
        end
      rescue StandardError => e
        Rails.logger.warn("[SchedulerWatchdog] #{e.class}: #{e.message}")
      end
    end
  end
end
