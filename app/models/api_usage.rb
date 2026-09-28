# Upwork's published ceiling is 40,000 requests a day. We stop well short of it
# rather than discovering the limit by hitting it.
class ApiUsage < ApplicationRecord
  self.table_name = "api_usages"

  def self.today
    find_or_create_by!(on: Date.current)
  end

  def self.record!(n = 1)
    today.increment!(:requests, n)
  end

  def self.used_today
    where(on: Date.current).pick(:requests).to_i
  end

  def self.budget_left
    Radar.daily_request_cap - used_today
  end

  def self.room_for?(n)
    budget_left >= n
  end
end
