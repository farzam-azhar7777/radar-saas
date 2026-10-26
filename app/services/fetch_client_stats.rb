class FetchClientStats
  def self.call(...) = new(...).call

  def initialize(postings, source: JobSource.current)
    @postings = Array(postings)
    @source = source
  end

  def call
    @postings.each do |posting|
      break unless ApiUsage.room_for?(1)

      stats = @source.client_stats(posting.upwork_id)
      posting.update!(stats) if stats.present?
    rescue Upwork::Error => e
      Rails.logger.warn("[FetchClientStats] posting #{posting.id}: #{e.message}")
    end
  end
end
