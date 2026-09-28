# Runtime switches the person can flip without restarting anything.
class Setting < ApplicationRecord
  AUTO_GENERATE = "auto_generate".freeze
  NATIVE_NOTIFICATIONS = "native_notifications".freeze

  # Chosen during setup, all revisitable from Settings.
  POLLING      = "polling".freeze
  CLAUDE_PATH  = "claude_path".freeze
  WRITER_MODEL = "writer_model".freeze
  DAILY_CAP    = "daily_generation_cap".freeze
  ACTIVE_FROM  = "active_from_hour".freeze
  ACTIVE_TO    = "active_to_hour".freeze

  def self.get(key, default = nil)
    find_by(key: key)&.value || default
  end

  def self.set(key, value)
    find_or_initialize_by(key: key).update!(value: value.to_s)
  end

  def self.clear(key)
    where(key: key).delete_all
  end

  # Off means: polling, scoring and notifications all continue, but no proposal
  # is written unless the person presses Write themselves.
  def self.auto_generate?
    get(AUTO_GENERATE, "on") == "on"
  end

  # The browser is the primary alert path: Chrome prompts for permission
  # properly, where a CLI tool never gets asked and is silently dropped. The
  # native path still works here, so it stays behind a switch for the case
  # where no tab is open.
  def self.native_notifications?
    get(NATIVE_NOTIFICATIONS, "off") == "on"
  end

  def self.toggle_native_notifications!
    set(NATIVE_NOTIFICATIONS, native_notifications? ? "off" : "on")
    native_notifications?
  end

  # Off pauses the automatic checks of Upwork. Pressing Check now still
  # works, and nothing already found or written is affected.
  def self.auto_polling?
    get(POLLING, "on") == "on"
  end

  def self.toggle_auto_polling!
    set(POLLING, auto_polling? ? "off" : "on")
    Setting.clear(PollTickJob::NEXT_POLL_AT) if auto_polling?
    auto_polling?
  end

  def self.toggle_auto_generate!
    set(AUTO_GENERATE, auto_generate? ? "off" : "on")
    auto_generate?
  end
end
