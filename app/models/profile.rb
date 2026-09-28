# The one person this install belongs to.
#
# Radar was written for a single freelancer and said his name in every prompt.
# Everything that was hardcoded about him is read from here, and the career
# folder's profile.yml and CLAUDE.md are rendered from it, so the proposal
# engine reads the same files it always did.
class Profile < ApplicationRecord
  REQUIRED = %i[full_name title country timezone skills].freeze

  validates :full_name, :title, :country, :timezone, presence: { message: "is needed" }, on: :setup
  validate :enough_skills, on: :setup
  validate :timezone_is_real, if: -> { timezone.present? }
  validates :hourly_rate, numericality: { greater_than: 0 }, allow_nil: true
  validates :hours_per_week, numericality: { in: 1..80 }, allow_nil: true

  # There is only ever one. A missing row reads as an empty profile rather than
  # raising, so every caller can ask for a name before setup is done.
  def self.current
    first || new
  end

  def self.first_name = current.first_name

  def complete? = REQUIRED.all? { |f| self[f].present? }

  def first_name
    preferred_name.presence || full_name.to_s.split.first.presence || "the freelancer"
  end

  # Every form of the name a self-introduction could use, for the check that
  # stops a proposal opening with one.
  def name_variants
    [ first_name, preferred_name, full_name, *full_name.to_s.split ].compact_blank
      .map(&:downcase).uniq.reject { |n| n == "the freelancer" || n.length < 2 }
  end

  # The profession line under the name. Titles are often long, pipe- or
  # dash-separated taglines; the signature wants only the first clause.
  def short_title
    title.to_s.split(/\s+[|—–-]\s+|,/).first.to_s.strip
  end

  def default_signature
    return nil if full_name.blank?

    [ UnicodeBold.italic(full_name.strip), (UnicodeBold.italic(short_title) if short_title.present?) ].compact.join("\n")
  end

  def signature_text = signature.presence || default_signature

  def skills_list
    skills.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?).uniq(&:downcase)
  end

  def languages_list
    languages.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end

  def samples
    Array(voice_samples).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def tz
    TZInfo::Timezone.get(timezone) if timezone.present?
  rescue TZInfo::InvalidTimezoneIdentifier
    nil
  end

  # "Asia/Karachi (UTC+5)", which is how people read a timezone.
  def timezone_label
    return nil unless (zone = tz)

    offset = zone.current_period.utc_total_offset / 3600.0
    sign = offset.negative? ? "-" : "+"
    hours = offset.abs % 1 == 0 ? offset.abs.to_i : offset.abs
    "#{timezone} (UTC#{sign}#{hours})"
  end

  def location_label = [ city.presence, country.presence ].compact.join(", ")

  private

  # Job scoring matches posts against these. Two is the least that says what
  # kind of work to look for.
  def enough_skills
    errors.add(:skills, "needs at least two, separated by commas") if skills_list.size < 2
  end

  def timezone_is_real
    errors.add(:timezone, "is not a timezone Radar recognises") if tz.nil?
  end
end
