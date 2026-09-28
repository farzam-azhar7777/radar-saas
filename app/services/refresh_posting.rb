# Re-fetches one job's live competition numbers.
#
# Upwork has no "get this job's stats by id" endpoint we can reach: the detail
# query exposes totalApplicants only under scopes we were not granted, and
# marketplaceJobPostingsContents blocks the same field. The only source is the
# search result, so we search for a distinctive phrase from the title and match
# the id in the results. One API call.
class RefreshPosting
  # Words that appear in thousands of titles and identify nothing.
  GENERIC = %w[
    senior junior lead principal staff expert experienced
    developer engineer development programmer coder consultant specialist
    full-stack fullstack full stack front-end frontend back-end backend
    needed wanted required hiring hire looking for a an the to and or of
    freelance remote urgent asap long-term part-time contract project work
    job posting
  ].freeze

  PHRASE_WORDS = 3
  PAGE = 50

  Result = Struct.new(:found, :changes, :message, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(posting, source: JobSource.current)
    @posting = posting
    @source = source
  end

  def call
    row = lookup
    return Result.new(found: false, changes: {}, message: "Could not find this job on Upwork. It may have been closed or filled.") if row.nil?

    changes = apply(row)
    Result.new(found: true, changes: changes, message: summary(changes))
  rescue Upwork::Error => e
    Result.new(found: false, changes: {}, message: "Upwork did not answer: #{e.message.truncate(90)}")
  end

  private

  # A short distinctive phrase beats the whole title. The full title fails as an
  # exact phrase whenever it contains punctuation Upwork normalises away.
  def expressions
    words = @posting.title.to_s.gsub(/[^\w\s\/.+-]/, " ").squeeze(" ").split
    meaningful = words.reject { |w| GENERIC.include?(w.downcase) }

    [
      (%("#{meaningful.first(PHRASE_WORDS).join(' ')}") if meaningful.size >= 2),
      (%("#{meaningful.first(2).join(' ')}") if meaningful.size >= 2),
      words.first(6).join(" ").presence
    ].compact.uniq
  end

  def lookup
    expressions.each do |expr|
      rows = @source.fetch(expr, PAGE)
      hit = rows.find { |r| r["upwork_id"] == @posting.upwork_id }
      return hit if hit
    end
    nil
  end

  TRACKED = %w[
    total_applicants already_applied client_total_spent client_total_hires
    client_rating client_payment_verified hourly_min hourly_max fixed_amount
  ].freeze

  def apply(row)
    @posting.applicants_at_discovery ||= @posting.total_applicants

    changes = {}
    TRACKED.each do |field|
      was = @posting.public_send(field)
      now = row[field]
      next if now.nil?
      next if was.to_s == now.to_s

      changes[field] = [ was, now ]
      @posting.public_send("#{field}=", now)
    end

    @posting.refreshed_at = Time.current

    # More competition can change the shape the proposal should take, so the
    # score is recomputed rather than left stale.
    if @posting.saved_search
      outcome = ScoreJobPosting.call(@posting, saved_search: @posting.saved_search)
      changes["score"] = [ @posting.score, outcome.score ] if @posting.score != outcome.score
      @posting.score = outcome.score
      @posting.score_reasons = outcome.reasons
    end

    @posting.save!
    changes
  end

  def summary(changes)
    # Ordered by what Farzam would want to know first. Having already applied
    # outranks everything, because it means he can stop reading.
    return "You have already applied to this one." if changes["already_applied"]&.last

    if (bids = changes["total_applicants"])
      delta = bids[1].to_i - bids[0].to_i
      return "Now #{bids[1]} #{'bid'.pluralize(bids[1].to_i)}, up #{delta} since you last looked." if delta.positive?
      return "Now #{bids[1]} #{'bid'.pluralize(bids[1].to_i)}, down #{delta.abs}." if delta.negative?
    end

    # The score drifts on its own as a posting ages. That is a recalculation,
    # not news, so it never counts as "something changed" on its own.
    news = changes.keys - [ "score" ]
    return "Nothing has changed." if news.empty?

    "Updated: #{news.map { |k| k.tr('_', ' ') }.to_sentence}."
  end
end
