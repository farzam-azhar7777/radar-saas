# What a client would call a product, built from one or more repositories.
#
#   candidate  found, ranked, waiting for the person to choose it or not
#   excluded   the person said no, and a rescan remembers that
#   queued     chosen, waiting for a writer
#   writing    Claude is writing it up
#   drafted    written, waiting for the person to accept it
#   accepted   in the career folder, so proposals can cite it
#   failed     the write-up broke; error says why, and it can be retried
class Knowledge::Project < ApplicationRecord
  STATUSES = %w[candidate excluded queued writing drafted accepted failed].freeze
  IN_FLIGHT = %w[queued writing].freeze

  # A write-up in flight longer than this is not running: the worker died
  # under it (a laptop sleeping), and a card that says "writing" forever is
  # worse than one that says it stopped.
  #
  # Measured from when writing began, not from when it was queued. Write-ups
  # run three at a time, so the twentieth waits behind the other nineteen,
  # and counting that wait once marked a healthy project as stuck. Writing is
  # capped by the writer's own timeout; a queue that has not moved for hours
  # means the worker is down.
  WRITING_STALE_AFTER = (Knowledge::Synthesizer::TIMEOUT + 300).seconds
  QUEUED_STALE_AFTER = 2.hours

  belongs_to :scan, class_name: "Knowledge::Scan", foreign_key: :knowledge_scan_id, optional: true
  has_many :repos, -> { order(own_commits: :desc) }, class_name: "Knowledge::Repo",
           foreign_key: :knowledge_project_id, dependent: :nullify, inverse_of: :project

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ranked, -> { order(rank_score: :desc, own_commits: :desc) }
  scope :accepted, -> { where(status: "accepted") }
  scope :drafted, -> { where(status: "drafted") }
  scope :in_flight, -> { where(status: IN_FLIGHT) }
  scope :visible, -> { where.not(status: "excluded") }

  before_validation { self.slug = self.class.slugify(name) if name.present? && (slug.blank? || will_save_change_to_name?) }

  def self.slugify(text)
    text.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "").first(60).presence || "project"
  end

  def self.span(from, to)
    return nil if from.blank?

    a = from.year
    b = to&.year || a
    return "#{a}" if a == b
    return "#{a}-present" if to && to > 3.months.ago

    "#{a}-#{b}"
  end

  def file = "#{slug}.yml"

  def span_label = self.class.span(first_at, last_at)

  def share
    return nil if total_commits.to_i.zero?

    ((own_commits.to_f / total_commits) * 100).round
  end

  def primary_repo = repos.first

  # Every tool across its repos, deduped, most-used repo first.
  def stack
    merged = Hash.new { |h, k| h[k] = [] }
    repos.each { |r| (r.stack || {}).each { |group, names| merged[group] |= Array(names) } }
    merged
  end

  def stack_names = Knowledge::StackDetector.flatten(stack)

  def in_flight? = IN_FLIGHT.include?(status) && !stale?

  def stale?
    case status
    when "writing" then writing_since < WRITING_STALE_AFTER.ago
    when "queued" then queued_at.present? && queued_at < QUEUED_STALE_AFTER.ago
    else false
    end
  end

  # The job stamps updated_at when it moves the project to "writing" and does
  # not touch it again until it finishes.
  def writing_since = updated_at || queued_at || Time.current

  # "Writing, 3 min" or "Waiting, 4th in line", so a slow write-up and a stuck
  # one never look the same.
  def progress_label
    if status == "writing"
      minutes = ((Time.current - writing_since) / 60).floor
      minutes < 1 ? "Writing, just started" : "Writing, #{minutes} min"
    else
      ahead = self.class.where(status: "queued").where("queued_at < ?", queued_at).count
      "Waiting, #{(ahead + 1).ordinalize} in line"
    end
  end

  def draft
    return {} if draft_yaml.blank?

    YAML.safe_load(draft_yaml, permitted_classes: [ Date, Time ]) || {}
  rescue Psych::Exception
    {}
  end

  # Commits made since it was written up, so the person can see a write-up has
  # gone stale.
  def new_commits_since_written
    return 0 if own_commits_when_written.nil?

    [ own_commits.to_i - own_commits_when_written, 0 ].max
  end

  def queue!(note: nil)
    update!(status: "queued", included: true, queued_at: Time.current, note: note, error: nil)
    Knowledge::WriteProjectJob.perform_later(self)
  end

  def accept!(yaml = draft_yaml)
    update!(draft_yaml: yaml, status: "accepted", accepted_at: Time.current)
    Knowledge::Publisher.call
  end

  # Taking one back out of the career folder, so proposals stop citing it.
  def unaccept!
    update!(status: "drafted", accepted_at: nil)
    CareerFolder.remove_project!(file)
    Knowledge::Publisher.call
  end

  def exclude!
    was_accepted = status == "accepted"
    update!(status: "excluded", included: false)
    return unless was_accepted

    CareerFolder.remove_project!(file)
    Knowledge::Publisher.call
  end
end
