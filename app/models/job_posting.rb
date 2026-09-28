class JobPosting < ApplicationRecord
  belongs_to :saved_search, optional: true
  has_many :proposals, -> { order(version: :desc) }, dependent: :destroy

  STATUSES = %w[new matched ignored dismissed applied generation_failed].freeze

  # What happened after he sent it. Reading nicely is not the same as winning,
  # and this is the only thing that tells the difference.
  OUTCOMES = {
    "no_reply"    => "No reply",
    "replied"     => "Client replied",
    "interviewed" => "Interviewed",
    "hired"       => "Hired"
  }.freeze

  validates :upwork_id, presence: true, uniqueness: true
  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :inbox,        -> { where(status: %w[matched generation_failed]).order(published_at: :desc) }
  scope :filtered_out, -> { where(status: "ignored").order(score: :desc) }
  scope :applied,      -> { where(status: "applied").order(applied_at: :desc) }
  scope :dismissed,    -> { where(status: "dismissed").order(published_at: :desc) }
  scope :awaiting_digest, -> { where(status: "matched", notified_at: nil) }

  # Free-text filter across everything a person would recognise a job by.
  scope :matching, ->(term) {
    next all if term.blank?

    like = "%#{term.to_s.strip.downcase}%"
    where("LOWER(title) LIKE :q OR LOWER(description) LIKE :q OR LOWER(skills) LIKE :q " \
          "OR LOWER(COALESCE(client_country, \'\')) LIKE :q OR LOWER(COALESCE(category, \'\')) LIKE :q", q: like)
  }

  # Ordering people actually want when triaging bids. "Fewest bids" is the one
  # that has no equivalent on Upwork itself.
  SORTS = {
    "newest"      => [ "Newest",      Arel.sql("published_at DESC") ],
    "fit"         => [ "Best fit",    Arel.sql("score DESC, published_at DESC") ],
    "competition" => [ "Fewest bids", Arel.sql("COALESCE(total_applicants, 999999) ASC, published_at DESC") ],
    "budget"      => [ "Best paid",   Arel.sql("COALESCE(fixed_amount, hourly_max, hourly_min, 0) DESC, score DESC") ]
  }.freeze

  scope :sorted_by, ->(key) { order(SORTS.fetch(key.to_s, SORTS["newest"]).last) }

  def latest_proposal
    proposals.first
  end

  def proposal_ready?
    latest_proposal&.body.present?
  end

  # Competition pressure: applicants per hour since posting. The single most
  # decision-relevant number when bidding, and the thing the inbox leads with.
  def applicants_per_hour
    return nil if total_applicants.blank? || published_at.blank?

    hours = [ (Time.current - published_at) / 3600.0, 0.25 ].max
    (total_applicants / hours).round(1)
  end

  # 0.0 (wide open) to 1.0 (crowded), for the gauge in the inbox.
  def pressure
    return 0.0 if total_applicants.blank?

    [ total_applicants / 50.0, 1.0 ].min.round(2)
  end

  def pressure_label
    return "No bids yet" if total_applicants.to_i.zero?

    "#{total_applicants} #{'bid'.pluralize(total_applicants)}"
  end

  def screening_questions_list = Array(screening_questions).map(&:to_s).reject(&:blank?)

  OPEN_TO_ALL = %w[Worldwide Anywhere].freeze

  # Where the person works from, as set in their profile.
  def self.home_country = Profile.current.country.presence

  def location_blocked?
    preferred_location_mandatory? && location_mismatch?
  end

  # Upwork's mandatory flag is the exception, not the rule: of the first eight
  # geo-restricted postings Radar wrote for, every one had it set false while
  # the post itself asked for a specific country. A client listing "Poland" or
  # a LatAm timezone spread is not going to hire from elsewhere, and a proposal
  # costs real money, so this is worth refusing to spend on even when Upwork
  # has not marked it mandatory. The person can still write one by hand.
  #
  # With no country in the profile there is nothing to compare, so nothing is
  # refused.
  def location_mismatch?
    locations = Array(preferred_locations).map(&:to_s).reject(&:blank?)
    home = self.class.home_country
    return false if locations.empty? || home.nil?

    home_names = [ home, CountryName.call(home) ].compact
    locations.none? { |c|
      home_names.any? { |h| c.casecmp?(h) || CountryName.call(c).to_s.casecmp?(h) } ||
        OPEN_TO_ALL.any? { |w| c.casecmp?(w) }
    }
  end

  def location_label = Array(preferred_locations).join(", ")

  # Questions the client buried in the description. Unlike screening questions
  # these get no boxes of their own on Upwork, so their answers have to live
  # inside the cover letter.
  def inline_questions
    @inline_questions ||= DescriptionQuestions.call(self)
  end

  def inline_questions? = inline_questions.any?

  # A hot match is worth interrupting him for. Everything else waits for a digest.
  def hot?
    saved_search.present? && score.to_i >= saved_search.hot_threshold.to_i
  end

  # A generation that has been queued longer than it could possibly take is not
  # running. The worker can die between enqueue and completion (laptop sleep,
  # a restart), and SolidQueue raises ProcessPrunedError from the supervisor,
  # outside the job, so the job's own rescue never runs and the flag was left
  # set forever. Time-bounding this means the UI stops lying immediately,
  # whether or not anything has swept yet.
  def self.generation_deadline = (Radar.generation_timeout + 300).seconds.ago

  # A rewrite runs while an older proposal is still on screen, so "has a
  # proposal" cannot mean "not generating". What ends a generation is a proposal
  # newer than the request that started it.
  def generation_superseded?
    return false if generation_queued_at.blank?

    finished = latest_proposal&.finished_at
    finished.present? && finished > generation_queued_at
  end

  def generating?
    return false if generation_queued_at.blank?
    return false if generation_queued_at <= self.class.generation_deadline

    !generation_superseded?
  end

  # Queued, never finished, and past the point where it could still be running.
  def generation_stale?
    return false if generation_queued_at.blank?
    return false if generation_superseded?

    generation_queued_at <= self.class.generation_deadline
  end

  # How long the current generation has been running, for the live progress UI.
  def generating_for
    return nil unless generating?

    Time.current - generation_queued_at
  end

  # Upwork job URLs are built from the ciphertext slug. Fall back to a stored
  # url, then to a search, so the button is never dead.
  def upwork_url
    return job_url if job_url.present?
    return "https://www.upwork.com/jobs/#{ciphertext}" if ciphertext.present?

    "https://www.upwork.com/nx/search/jobs/?q=#{CGI.escape(title)}"
  end

  def budget_label
    if contract_type.to_s.downcase.include?("fixed") && fixed_amount.present?
      "$#{fixed_amount.to_i} fixed"
    elsif hourly_min.present? || hourly_max.present?
      lo = hourly_min&.to_i
      hi = hourly_max&.to_i
      return "$#{lo}-#{hi}/hr" if lo && hi && lo != hi
      "$#{(hi || lo)}/hr"
    else
      "Budget not stated"
    end
  end

  def age_label
    return "unknown" if published_at.blank?

    mins = ((Time.current - published_at) / 60).to_i
    return "#{mins}m ago" if mins < 60
    return "#{mins / 60}h ago" if mins < 1440
    "#{mins / 1440}d ago"
  end

  # Under an hour is where the early-applicant advantage actually lives.
  def urgent?
    published_at.present? && published_at > 1.hour.ago
  end

  # A client's timezone decides whether a long-term role is actually workable,
  # and Upwork's own panel does not tell you the overlap. Measured against the
  # person's own zone from their profile.
  WORKDAY = (9...18)

  def client_country_name = CountryName.call(client_country)

  def client_location
    [ client_city.presence, client_country_name ].compact.join(", ").presence
  end

  # Upwork shows this as "100% hire rate". It is hires over jobs posted, and it
  # separates a client who hires from one who collects proposals and vanishes.
  def client_hire_rate
    posted = client_total_posted_jobs.to_i
    return nil unless posted.positive?

    ((client_total_hires.to_f / posted) * 100).round
  end

  def client_avg_per_hire
    hires = client_total_hires.to_i
    return nil unless hires.positive? && client_total_spent.to_f.positive?

    (client_total_spent.to_f / hires).round
  end

  # Hours of a 9-to-6 working day that overlap with theirs.
  def client_overlap_hours
    return nil if client_timezone.blank?

    theirs = TZInfo::Timezone.get(client_timezone)
    mine = TZInfo::Timezone.get(Radar.timezone)
    now = Time.current
    shift = ((theirs.period_for_utc(now).offset.utc_total_offset -
              mine.period_for_utc(now).offset.utc_total_offset) / 3600.0).round

    (WORKDAY.to_a & WORKDAY.to_a.map { |h| h + shift }).size
  rescue StandardError
    nil
  end

  def client_local_time
    return nil if client_timezone.blank?

    TZInfo::Timezone.get(client_timezone).to_local(Time.current).strftime("%-l:%M %p")
  rescue StandardError
    nil
  end

  def client_label
    parts = []
    parts << client_country_name if client_country.present?
    parts << "$#{client_total_spent.to_i} spent" if client_total_spent.present?
    parts << "#{client_total_hires} hires"       if client_total_hires.present?
    parts << "#{client_rating.to_f.round(1)}★"   if client_rating.present?
    parts << (client_payment_verified ? "verified" : "unverified") unless client_payment_verified.nil?
    parts.join(" · ").presence || "No client history"
  end

  def outcome_label = OUTCOMES[outcome]

  def won? = %w[interviewed hired].include?(outcome)

  def slug
    title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "").first(60)
  end
end
