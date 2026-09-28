# One projects folder, and how far Radar has got through it.
#
#   discovering   finding git repos and who committed to them
#   identities    waiting for the person to say which authors are them
#   inventorying  reading every repo's history, deterministically
#   curating      waiting for the person to choose projects
#   writing       Claude is writing up the chosen projects
#   failed        something broke; error says what
class Knowledge::Scan < ApplicationRecord
  STATUSES = %w[discovering identities inventorying curating writing failed].freeze
  BUSY = %w[discovering inventorying].freeze

  has_many :repos, class_name: "Knowledge::Repo", foreign_key: :knowledge_scan_id, dependent: :destroy
  has_many :projects, class_name: "Knowledge::Project", foreign_key: :knowledge_scan_id, dependent: :destroy

  validates :root_path, presence: true
  validates :status, inclusion: { in: STATUSES }

  def self.current = order(:created_at).last

  def busy? = BUSY.include?(status)

  def identity_emails = Array(identities).map { |e| e.to_s.downcase.strip }.reject(&:blank?)
  def identity_names  = Array(names).map { |n| n.to_s.downcase.strip }.reject(&:blank?)

  # A commit is theirs if either its email or its name is one they claimed.
  # Names matter: the same person commits from a laptop, a work account and
  # GitHub's noreply address, and the name is often the only thing in common.
  def own?(email, name)
    identity_emails.include?(email.to_s.downcase.strip) || identity_names.include?(name.to_s.downcase.strip)
  end

  def progress_percent
    return 0 if progress_total.to_i.zero?

    ((progress_done.to_f / progress_total) * 100).round.clamp(0, 100)
  end

  def progress!(done, total = progress_total, label = nil)
    update_columns(progress_done: done, progress_total: total, progress_label: label, updated_at: Time.current)
    broadcast
  end

  def broadcast
    Turbo::StreamsChannel.broadcast_refresh_to(self)
  rescue StandardError => e
    Rails.logger.warn("[Knowledge::Scan] broadcast failed: #{e.message}")
  end

  def root = Pathname.new(root_path)

  def own_repos = repos.where("own_commits > 0")
  def others_repos = repos.where(own_commits: 0)
end
