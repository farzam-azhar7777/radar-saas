# Recovers polling after a laptop sleep leaves the scheduler hung.
# Runs only in solid_queue's supervisor process. See app/services/scheduler_watchdog.rb.
Rails.application.config.after_initialize do
  SolidQueue::Supervisor.on_start { SchedulerWatchdog.start }
end
