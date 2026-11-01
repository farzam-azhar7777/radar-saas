class EarlierCopies
  WINDOW = 30.days
  SKIP_FROM = 2
  TITLE_LIKENESS = 0.8
  MAX_NEW_POSTS_BETWEEN = 40

  def self.call(posting) = new(posting).call

  def self.flag!(posting)
    copies = call(posting)
    return posting if copies.empty?

    first = copies.first
    posting.repost_of_id = first.repost_of_id || first.id
    posting.repost_count = copies.size
    posting
  end

  def self.pass_over_unwritten(posting)
    chain = JobPosting.where(id: [ posting.id, posting.repost_of_id ]).or(JobPosting.where(repost_of_id: posting.repost_of_id))
    chain.where(status: "matched", generation_queued_at: nil).where.missing(:proposals).each do |copy|
      copy.update!(status: "ignored", score_reasons: Array(copy.score_reasons) + [ posting.repost_reason ])
    end
  end

  def initialize(posting)
    @posting = posting
  end

  def call
    return [] if @posting.client_country.blank? || title_pairs.empty?

    seen_at = @posting.created_at || Time.current
    JobPosting.where(client_country: country_forms, created_at: (seen_at - WINDOW)...seen_at)
              .where.not(upwork_id: @posting.upwork_id)
              .order(:created_at)
              .select { |earlier| same_client?(earlier) && likeness(earlier) >= TITLE_LIKENESS }
  end

  private

  def country_forms
    raw = @posting.client_country
    name = CountryName.call(raw)
    [ raw, name, CountryName::CODES.key(name) ].compact.uniq
  end

  def same_client?(earlier)
    posted_since = @posting.client_total_posted_jobs.to_i - earlier.client_total_posted_jobs.to_i
    posted_since.between?(0, MAX_NEW_POSTS_BETWEEN) &&
      @posting.client_total_spent.to_f >= earlier.client_total_spent.to_f
  end

  def likeness(earlier)
    theirs = pairs(earlier.title)
    return 0.0 if theirs.empty?

    remaining = theirs.dup
    shared = title_pairs.count { |pair| (i = remaining.index(pair)) && remaining.delete_at(i) }
    2.0 * shared / (title_pairs.size + theirs.size)
  end

  def title_pairs = @title_pairs ||= pairs(@posting.title)

  def pairs(title)
    letters = title.to_s.downcase.gsub(/[^a-z0-9]+/, "")
    (0...[ letters.size - 1, 0 ].max).map { |i| letters[i, 2] }
  end
end
