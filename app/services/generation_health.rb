# Radar told Farzam a job was hot, then the proposal silently never arrived.
# Four generations failed over two days and nothing anywhere said so: he found
# them by noticing "Failed" while scrolling the inbox.
#
# A single job failing is normal. The writer being unable to run at all is not,
# and the two need to look different, because one is worth ignoring and the
# other means nothing will be written until a human acts.
module GenerationHealth
  module_function

  WINDOW = 2.hours

  # "Not logged in - Please run /login". The claude CLI keeps its credentials in
  # the macOS Keychain, and a worker forked before a sleep/wake cycle loses
  # access to it. The job then fails in about 100ms having done nothing.
  NOT_LOGGED_IN = /not logged in|please run \/login/i

  def recent_failures
    JobPosting.where(status: "generation_failed").where(updated_at: WINDOW.ago..)
  end

  def recent_successes
    Proposal.where(created_at: WINDOW.ago..).count
  end

  # True when every recent attempt failed for the same systemic reason, so the
  # next one will fail too.
  def blocked?
    failures = recent_failures
    return false if failures.count < 2

    recent_successes.zero? && failures.any? { |p| p.generation_error.to_s.match?(NOT_LOGGED_IN) }
  end

  def status
    return :blocked if blocked?
    return :degraded if recent_failures.count.positive?

    :ok
  end

  def message
    case status
    when :blocked
      "The writer cannot log in, so nothing is being written. " \
      "Run claude in a terminal to re-authenticate, then restart bin/dev so the worker picks it up."
    when :degraded
      n = recent_failures.count
      "#{n} #{'proposal'.pluralize(n)} failed to write in the last two hours. Open one to see why."
    end
  end
end
