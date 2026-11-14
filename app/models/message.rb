class Message < ApplicationRecord
  ROLES = %w[client me ask radar].freeze

  belongs_to :job_posting

  validates :role, inclusion: { in: ROLES }
  validates :body, presence: true

  def self.typical_reply_seconds
    runs = where(role: "me").order(id: :desc).limit(20).filter_map { |m| m.claude_meta.to_h["duration_api_ms"] }
    runs.any? ? (runs.sort[runs.size / 2] / 1000.0).ceil + 5 : 45
  end

  def client? = role == "client"
  def awaits_radar? = role.in?(%w[client ask])
  def drafted? = claude_meta.present?
end
