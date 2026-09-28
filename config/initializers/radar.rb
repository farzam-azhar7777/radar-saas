# Radar's own settings. Deliberately small and all overridable by env.
module Radar
  # The career folder the proposal engine reads: CLAUDE.md, profile.yml,
  # skills.yml, writing-voice.md, projects/ and templates/. The setup wizard
  # writes it. It lives inside storage/, which is gitignored, so nobody's work
  # history can be committed to the repository by accident.
  def self.career_path
    Pathname.new(ENV.fetch("RADAR_CAREER_PATH") { Rails.root.join("storage", "career").to_s }).expand_path
  end

  # Settable in the wizard for people whose claude is not on the server's PATH,
  # which is common when it was installed through a version manager.
  def self.claude_bin
    Setting.get(Setting::CLAUDE_PATH).presence || ENV.fetch("CLAUDE_BIN", "claude")
  rescue ActiveRecord::ActiveRecordError
    ENV.fetch("CLAUDE_BIN", "claude")
  end

  def self.port = Integer(ENV.fetch("PORT", 8586))

  def self.url_options = { host: "localhost", port: port }

  # --- polling cadence -------------------------------------------------
  # Budgeted at roughly 418 Upwork calls a day, about 1% of their 40,000
  # ceiling. One combined search per cycle covers every saved search, because
  # BestSearchFor assigns postings to searches locally.
  def self.active_interval  = Integer(ENV.fetch("RADAR_ACTIVE_INTERVAL_SECONDS", 180))   # 3 min
  def self.night_interval   = Integer(ENV.fetch("RADAR_NIGHT_INTERVAL_SECONDS", 1200))   # 20 min
  # Chosen in setup. Hours past 24 run into the next morning, so 7..25 is
  # "from 7am until 1am".
  def self.active_hours
    from = setting_int(Setting::ACTIVE_FROM) || Integer(ENV.fetch("RADAR_ACTIVE_FROM_HOUR", 7))
    to   = setting_int(Setting::ACTIVE_TO) || Integer(ENV.fetch("RADAR_ACTIVE_TO_HOUR", 25))
    to += 24 if to <= from
    from..to
  end

  def self.setting_int(key)
    value = Setting.get(key)
    value.present? ? Integer(value) : nil
  rescue ActiveRecord::ActiveRecordError, ArgumentError
    nil
  end
  # The person's own zone, so the quiet overnight cadence lands on their night.
  def self.timezone
    Profile.current.timezone.presence || ENV.fetch("RADAR_TIMEZONE", "UTC")
  rescue ActiveRecord::ActiveRecordError
    ENV.fetch("RADAR_TIMEZONE", "UTC")
  end

  # Machine-perfect intervals look like a bot. Everything is jittered.
  def self.jitter_fraction  = Float(ENV.fetch("RADAR_JITTER", 0.25))

  # One page of 50 reaches back about two hours at the observed posting rate,
  # so a 3 minute cycle has roughly 40x headroom.
  def self.page_size        = Integer(ENV.fetch("RADAR_PAGE_SIZE", 50))

  # --- budgets ---------------------------------------------------------
  def self.daily_request_cap        = Integer(ENV.fetch("RADAR_DAILY_REQUEST_CAP", 30_000))
  def self.max_generations_per_poll = Integer(ENV.fetch("RADAR_MAX_GENERATIONS_PER_POLL", 5))
  def self.daily_generation_cap     = setting_int(Setting::DAILY_CAP) || Integer(ENV.fetch("RADAR_DAILY_GENERATION_CAP", 15))
  def self.generation_timeout       = Integer(ENV.fetch("RADAR_GENERATION_TIMEOUT", 900))
  # Seconds from the start of a generation after which nothing more is fixed.
  # A repair gets only what is left, and none starts with under a minute to go:
  # the draft ships with what is still wrong listed beside it. Before this, plan,
  # draft, repair and a full rewrite each had their own timeout, and together
  # they reached ten minutes.
  def self.generation_deadline = Integer(ENV.fetch("RADAR_GENERATION_DEADLINE", 420))

  # The model that writes proposals and repairs them. Pinned, because the
  # claude CLI's own default moved from Opus 4.7 to Opus 5 on 2026-09-24
  # without anything here changing.
  #
  # Chosen 2026-09-25 from a blind comparison on three real jobs, same prompt:
  #   Fable 5.1  best on 2 of 3, 315-520s, ~3x the allowance of Opus
  #   Opus 5     best on 1, second on 2, 119-238s     <- default
  #   Sonnet 5   third on all three, 163-193s, ~half of Opus
  #   Opus 4.7   last on all three, and once over Upwork's 5000 characters
  # Fable's lead was small; its wait and its draw on the Max plan were not.
  #
  # Setup tests this exact model against the person's own Claude login. If
  # their plan cannot use it, they choose the CLI default instead, stored as
  # the literal "default".
  DEFAULT_WRITER_MODEL = "claude-opus-5".freeze

  def self.writer_model
    chosen = Setting.get(Setting::WRITER_MODEL).presence
    return nil if chosen == "default"

    chosen || ENV.fetch("RADAR_WRITER_MODEL", DEFAULT_WRITER_MODEL).presence
  rescue ActiveRecord::ActiveRecordError
    ENV.fetch("RADAR_WRITER_MODEL", DEFAULT_WRITER_MODEL).presence
  end

  # Median observed across real generations, for pacing the progress bar.
  def self.typical_generation_seconds = Integer(ENV.fetch("RADAR_TYPICAL_GENERATION", 160))

  # Rewriting one part sends the job, that part and the note, instead of the
  # whole spec and the whole draft, so it lands in a fraction of the time.
  def self.typical_section_seconds = Integer(ENV.fetch("RADAR_TYPICAL_SECTION", 45))

  # Plan once, then write the parts at the same time.
  #
  # OFF by default, honestly. The premise was that token generation dominates
  # the wall clock, so generating the parts concurrently would cut it. Measured
  # on live jobs, the premise was wrong: writing every part in parallel takes
  # 15 to 39 seconds, while deciding what to write takes 200 to 420. Prose was
  # never the bottleneck, so parallelising it bought little and cost about
  # twice as much, because the plan and five writers each resend context.
  #
  # The one measurement that did move: planning on a faster model, 421s to
  # 208s. Planning is decision-making against a fixed schema, so it is the one
  # phase where a smaller model risks nothing about his voice.
  #
  # Turn it on with RADAR_PARALLEL_GENERATION=1, ideally with RADAR_PLAN_MODEL
  # set, and compare before trusting it.
  def self.parallel_generation? = ENV.fetch("RADAR_PARALLEL_GENERATION", "0") == "1"

  # --- digest ----------------------------------------------------------
  def self.digest_size        = Integer(ENV.fetch("RADAR_DIGEST_SIZE", 8))
  def self.digest_after_hours = Float(ENV.fetch("RADAR_DIGEST_AFTER_HOURS", 3))

  # Seconds until the next poll, jittered, and longer while they are asleep.
  def self.next_interval(now = Time.current)
    hour = now.in_time_zone(timezone).hour
    base = active_hours.cover?(hour) || active_hours.cover?(hour + 24) ? active_interval : night_interval
    spread = base * jitter_fraction
    (base + rand(-spread..spread)).round.clamp(30, 3600)
  end
end
