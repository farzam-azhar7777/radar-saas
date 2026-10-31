class JobLimits
  SETTING = "job_limits".freeze
  RECENT_DAYS = 7

  Stat = Data.define(:key, :group, :label, :prefix, :suffix, :step, :reader) do
    def noun = group == "client" ? "Client #{label.downcase}" : label

    def format(value)
      number = value.to_f == value.to_i ? value.to_i : value.to_f.round(2)
      "#{prefix}#{ActiveSupport::NumberHelper.number_to_delimited(number)}#{suffix}"
    end
  end

  STATS = [
    Stat.new("hourly_rate", "job", "Hourly rate", "$", "/hr", 1, ->(p) {
      next nil if p.fixed_amount.present?
      rates = [ p.hourly_min, p.hourly_max ].compact.map(&:to_f).reject(&:zero?)
      rates.minmax if rates.any?
    }),
    Stat.new("fixed_price", "job", "Fixed price", "$", "", 1, ->(p) { p.fixed_amount&.to_f }),
    Stat.new("bids", "job", "Bids so far", "", "", 1, ->(p) { p.total_applicants }),
    Stat.new("hire_rate", "client", "Hire rate", "", "%", 1, ->(p) { p.client_hire_rate }),
    Stat.new("client_spent", "client", "Total spent", "$", "", 1, ->(p) { p.client_total_spent&.to_f }),
    Stat.new("client_rating", "client", "Rating", "", "★", 0.1, ->(p) { p.client_rating.to_f.positive? ? p.client_rating.to_f : nil }),
    Stat.new("client_jobs_posted", "client", "Jobs posted", "", "", 1, ->(p) { p.client_total_posted_jobs }),
    Stat.new("avg_per_hire", "client", "Average per hire", "$", "", 1, ->(p) { p.client_avg_per_hire })
  ].freeze

  BOUNDS = %w[min max].freeze
  GROUPS = { "job" => "The job", "client" => "The client" }.freeze

  def self.current = new(JSON.parse(Setting.get(SETTING, "{}")))

  def self.recent_matches
    JobPosting.where(created_at: RECENT_DAYS.days.ago..).includes(:saved_search)
              .select { |p| p.saved_search && p.score.to_i >= p.saved_search.threshold }
  end

  def self.stat(key) = STATS.find { |s| s.key == key.to_s }

  def self.clean(raw)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    (raw || {}).to_h.each_with_object({}) do |(key, bounds), out|
      next unless stat(key) && bounds.respond_to?(:to_h)

      kept = bounds.to_h.slice(*BOUNDS).filter_map { |bound, value|
        text = value.to_s.strip
        next if text.empty?

        number = Float(text, exception: false)
        [ bound, number.nil? ? text : (number == number.to_i ? number.to_i : number) ]
      }.to_h
      out[key] = kept if kept.any?
    end
  end

  def initialize(limits)
    @limits = self.class.clean(limits)
  end

  def to_h = @limits

  def save
    return false if errors.any?

    Setting.set(SETTING, @limits.to_json)
    true
  end

  def any? = @limits.any?

  def bound(key, which) = @limits.dig(key.to_s, which.to_s)

  def errors
    @limits.flat_map do |key, bounds|
      label = self.class.stat(key).noun.downcase
      problems = bounds.filter_map { |bound, value|
        "#{label} #{bound} must be a number" unless value.is_a?(Numeric)
      }
      problems += bounds.filter_map { |bound, value| "#{label} #{bound} cannot be negative" if value.is_a?(Numeric) && value.negative? }
      lo, hi = bounds.values_at("min", "max")
      problems << "#{label} min must be at or below its max" if lo.is_a?(Numeric) && hi.is_a?(Numeric) && lo > hi
      problems
    end
  end

  def breach(posting) = breaches(posting).first&.last

  def impact(postings)
    stats = postings.filter_map { |p| breaches(p).first&.first }
    { total: postings.size, passed_over: stats.size, by_stat: stats.map(&:noun).tally.sort_by { |_, n| -n } }
  end

  def breaches(posting)
    @limits.filter_map do |key, bounds|
      stat = self.class.stat(key)
      value = stat.reader.call(posting)
      next if value.nil?

      lo, hi = Array(value).minmax
      if bounds["min"].is_a?(Numeric) && hi < bounds["min"]
        [ stat, "#{stat.noun} #{stat.format(hi)}, under your #{stat.format(bounds['min'])} minimum" ]
      elsif bounds["max"].is_a?(Numeric) && lo > bounds["max"]
        [ stat, "#{stat.noun} #{stat.format(lo)}, over your #{stat.format(bounds['max'])} maximum" ]
      end
    end
  end

  def summary
    STATS.filter_map do |stat|
      bounds = @limits[stat.key] or next
      lo, hi = bounds.values_at("min", "max").map { |v| v && stat.format(v) }
      range = if lo && hi then "#{lo} to #{hi}"
      elsif lo then "at least #{lo}"
      else "at most #{hi}"
      end
      "#{stat.noun} #{range}"
    end
  end
end
