class Message < ApplicationRecord
  ROLES = %w[client me].freeze

  belongs_to :job_posting

  validates :role, inclusion: { in: ROLES }
  validates :body, presence: true

  def client? = role == "client"
  def drafted? = claude_meta.present?
end
