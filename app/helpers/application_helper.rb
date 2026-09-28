module ApplicationHelper
  # Generation costs real money, so it is never something you discover later.
  def todays_generation_stats
    today = Proposal.where(created_at: Time.current.all_day)
    { count: today.count,
      spend: today.sum { |p| p.claude_meta["total_cost_usd"].to_f },
      cap: Radar.daily_generation_cap }
  end

  # Fit, on a scale Farzam reads dozens of times a day. Only the top band gets
  # the signal colour, so it keeps meaning something.
  def score_tone(score)
    case score.to_i
    when 85..100 then %w[text-signal border-signal]
    when 75..84  then %w[text-ink border-ink]
    when 65..74  then %w[text-muted border-rule]
    else %w[text-faint border-rule]
    end
  end

  # The fit ring. Only the top band is coral, so it keeps meaning something.
  def dial_class(score)
    case score.to_i
    when 85..100 then "dial-strong"
    when 70..84 then "dial-good"
    when 55..69 then "dial-fair"
    else "dial-low"
    end
  end

  def gauge_tone(pressure)
    case pressure
    when 0.6.. then "!bg-signal"
    when 0.3...0.6 then "!bg-warn"
    else "!bg-good"
    end
  end

  # What happened to a note he wrote. Only a real failure gets the alarm
  # colour: a skip is usually the distiller being right.
  def feedback_tone(feedback)
    return "text-good" if feedback.learned?
    return "text-signal" if feedback.failed? || feedback.stalled?

    "text-muted"
  end

  # A placeholder that suggests what this particular part is usually wrong
  # about, so the box prompts rather than sitting there empty.
  def rewrite_placeholder(part)
    return "Answer the question in the first line. Cut the second half." if part.answer?
    return "Use #{example_project} instead. Drop the third project." if part.portfolio?

    case part.display_label.downcase
    when /open|hook|intro/  then "Lead with the commit count. Make the first line about their migration."
    when /skill/            then "Add Sidekiq and Postgres tuning. Four bullets, not six."
    when /ready|close|next|start/ then "Say I can start Monday. Shorter."
    when /signature/        then "Just the name, no title."
    else "Say what to change about this part only."
    end
  end

  # Their own strongest project, so an example note reads like one they would write.
  def example_project
    CareerData.instance.index_entries.first&.dig("name").presence || "your strongest project"
  end

  def nav_link(label, path, icon_name, count: nil, match: nil)
    on = current_page?(path) || (match && request.path.start_with?(match))
    link_to path, class: "nav-item", "aria-current": (on ? "page" : nil) do
      safe_join([ icon(icon_name), tag.span(label), (tag.span(count, class: "nav-count") if count&.positive?) ].compact)
    end
  end

  # "in 2 min", "now", or nil when nothing is scheduled.
  def next_check_label
    at = Time.zone.parse(Setting.get(PollTickJob::NEXT_POLL_AT).to_s)
    return nil unless at

    seconds = (at - Time.current).to_i
    seconds <= 30 ? "now" : "in #{distance_of_time_in_words(Time.current, at)}"
  rescue ArgumentError, TypeError
    nil
  end
end
