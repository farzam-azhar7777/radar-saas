# Native macOS notification. Behind a seam so a push transport can replace it
# if radar ever moves off the laptop.
class Notifier
  def self.notify(title:, message:, url: nil)
    new.notify(title: title, message: message, url: url)
  end

  def notify(title:, message:, url: nil)
    return false unless enabled?

    if terminal_notifier?
      cmd = [ "terminal-notifier", "-title", title, "-message", message,
              "-group", "radar", "-sound", "Glass" ]
      cmd += [ "-open", url ] if url.present?
      system(*cmd, out: File::NULL, err: File::NULL)
    else
      script = %(display notification #{message.to_json} with title #{title.to_json})
      system("osascript", "-e", script, out: File::NULL, err: File::NULL)
    end
  rescue StandardError => e
    Rails.logger.warn("[Notifier] #{e.class}: #{e.message}")
    false
  end

  private

  def enabled?
    Setting.native_notifications? && RUBY_PLATFORM.include?("darwin")
  end

  def terminal_notifier?
    @terminal_notifier ||= system("which", "terminal-notifier", out: File::NULL, err: File::NULL)
  end
end
