# Turns raw source attributes into scored JobPosting rows. Deduping, re-homing
# and scoring all happen here so the poll job stays about scheduling.
class IngestPostings
  ATTRS = %w[
    upwork_id ciphertext title description contract_type hourly_min hourly_max
    fixed_amount client_country client_payment_verified client_total_spent
    client_total_hires client_rating skills published_at raw_payload job_url
    total_applicants already_applied premium enterprise category subcategory
    experience_level engagement duration_label freelancers_to_hire
    preferred_locations preferred_location_mandatory
    client_city client_timezone client_total_posted_jobs client_total_reviews
    client_last_contract_title client_financial_privacy
  ].freeze

  def self.call(...) = new(...).call

  def initialize(rows, searches: SavedSearch.active.ordered.to_a)
    @rows = Array(rows)
    @searches = searches
  end

  # Returns only the postings that cleared their search's threshold.
  def call
    return [] if @searches.empty?

    seen = JobPosting.where(upwork_id: @rows.map { |r| r["upwork_id"] }).pluck(:upwork_id).to_set
    matched = []

    @rows.each do |attrs|
      id = attrs["upwork_id"]
      next if id.blank? || seen.include?(id)

      seen << id
      posting = JobPosting.new(attrs.slice(*ATTRS))
      owner = BestSearchFor.call(posting, fallback: @searches.first, searches: @searches)
      posting.saved_search = owner

      outcome = ScoreJobPosting.call(posting, saved_search: owner, searches: @searches)
      posting.score = outcome.score
      posting.score_reasons = outcome.reasons

      # Upwork tells us when Farzam already bid. Those go straight to applied
      # rather than cluttering the inbox.
      posting.status =
        if posting.already_applied?  then "applied"
        elsif posting.location_blocked? then "ignored"
        elsif outcome.score >= owner.threshold then "matched"
        else "ignored"
        end
      posting.applied_at = Time.current if posting.status == "applied"

      matched << posting if posting.save && posting.status == "matched"
    end

    matched
  end
end
