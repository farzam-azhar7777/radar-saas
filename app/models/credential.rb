# A secret the person entered in setup, encrypted at rest.
#
# Only the Upwork app key lives here today. It is deliberately separate from
# Setting, which holds plain switches and is safe to show on screen.
class Credential < ApplicationRecord
  encrypts :value

  validates :key, presence: true, uniqueness: true

  UPWORK_FIELDS = %i[client_id client_secret redirect_uri tenant_id].freeze

  def self.get(key)
    find_by(key: key.to_s)&.value
  end

  # Blank clears it, so a form can remove an optional field.
  def self.set(key, value)
    record = find_or_initialize_by(key: key.to_s)
    return record.destroy if value.blank? && record.persisted?
    return nil if value.blank?

    record.update!(value: value.to_s.strip)
  end

  # The shape Upwork::Client always read from credentials.yml.enc.
  def self.upwork
    UPWORK_FIELDS.to_h { |f| [ f, get("upwork.#{f}") ] }.compact_blank
  end

  def self.set_upwork(attrs)
    UPWORK_FIELDS.each do |field|
      next unless attrs.key?(field) || attrs.key?(field.to_s)

      set("upwork.#{field}", attrs[field] || attrs[field.to_s])
    end
  end

  # Shown in place of a saved secret, so the page proves it is stored without
  # ever sending it back to the browser.
  def self.masked(key)
    value = get(key).to_s
    return nil if value.blank?

    value.length <= 8 ? "••••" : "#{value.first(4)}••••#{value.last(4)}"
  end
end
