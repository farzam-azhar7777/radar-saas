# Plain Ruby, no LLM, no cost, no network. Deterministic and inspectable:
# every point that lands in the score also lands in score_reasons, so tuning
# is something Farzam can see rather than guess at.
class ScoreJobPosting
  Result = Struct.new(:score, :reasons, keyword_init: true)

  # Below this a fixed-price job is not worth the Connects, let alone the
  # dollar it costs to write a proposal for it.
  DEFAULT_MIN_FIXED = 500

  def self.call(...) = new(...).call

  def initialize(posting, saved_search: nil, career: CareerData.instance, searches: nil)
    @posting = posting
    @search  = saved_search || posting.saved_search || SavedSearch.new
    @career  = career
    # Passed in by the ingest loop, which already has them. Loaded here only for
    # one-off rescoring, so the common path stays at zero extra queries.
    @searches = searches
  end

  def call
    return Result.new(score: 0, reasons: [ excluded_reason ]) if excluded?

    weights = @search.effective_weights
    parts = {
      "title_match"    => title_component,
      "skill_overlap"  => skill_component,
      "category_fit"   => CategoryFit.call(@posting),
      "project_tags"   => project_component,
      "budget"         => budget_component,
      "client_history" => client_component,
      "recency"        => recency_component
    }

    reasons = []
    total = 0.0

    parts.each do |key, (fraction, note)|
      weight = weights.fetch(key, 0).to_f
      points = (fraction * weight).round
      total += points
      reasons << { "key" => key, "points" => points, "max" => weight.round, "note" => note }
    end

    Result.new(score: total.round.clamp(0, 100), reasons: reasons)
  end

  private

  def haystack
    @haystack ||= TextMatch.haystack_for(@posting)
  end

  def title
    @title ||= TextMatch.title_of(@posting)
  end

  # The single strongest signal, and the one that was missing. A posting titled
  # "Senior Ruby on Rails Engineer" is unambiguously Farzam's work no matter
  # what its description rambles about, and an embedded-hardware post that
  # happens to mention DIN rails in prose is unambiguously not.
  # Does the title say this is Farzam's kind of work? That question is not
  # specific to one saved search, and scoring it only against the owner's terms
  # let re-homing destroy the strongest signal there is: "Full-Stack Engineer -
  # Health Care" was re-homed to Web application because its skills list said
  # "Web Application", and then scored 0 of 25 on a title that says full stack
  # engineer outright. The owner's own terms still rank highest, because they
  # are the most specific evidence.
  def title_component
    if (hit = exact_hit(@search.terms_list))
      return [ 1.0, "Title says #{hit.inspect}" ]
    end

    if (hit = exact_hit(other_terms))
      return [ 0.9, "Title says #{hit.inspect}, which is one of your other searches" ]
    end

    # A phrase interrupted by a word ("Full Stack HEALTHCARE Developer") is the
    # same job, but it is weaker evidence than the phrase said outright, so it
    # scores below an exact hit rather than equal to it.
    if (hit = split_hit(@search.terms_list))
      return [ 0.8, "Title says #{hit.inspect}, split by another word" ]
    end

    if (hit = split_hit(other_terms))
      return [ 0.72, "Title says #{hit.inspect}, split by another word" ]
    end

    skill_hits = @career.skill_terms.select { |t| t.length > 3 && TextMatch.includes?(title, t) }
    return [ 0.6, "Title mentions #{skill_hits.take(2).join(', ')}" ] if skill_hits.any?

    [ 0.0, "Title is not about this kind of work" ]
  end

  def exact_hit(terms) = terms.select { |t| TextMatch.includes?(title, t) }.max_by(&:length)

  def split_hit(terms)
    terms.select { |t| t.include?(" ") && TextMatch.spans?(title, t) }.max_by(&:length)
  end

  # Every active search except the one that owns this posting.
  def other_terms
    @other_terms ||= begin
      all = @searches || SavedSearch.active.to_a
      all.reject { |s| s.id == @search.id }.flat_map(&:terms_list).uniq
    end
  end

  def excluded?
    excluded_keyword.present? || excluded_country?
  end

  def excluded_keyword
    @search.excluded_keywords_list.find { |kw| TextMatch.includes?(haystack, kw) }
  end

  def excluded_country?
    Array(@search.excluded_countries).map(&:to_s).map(&:downcase)
      .include?(@posting.client_country.to_s.downcase) && @posting.client_country.present?
  end

  def excluded_reason
    if (kw = excluded_keyword)
      { "key" => "excluded", "points" => 0, "max" => 100, "note" => "Excluded by keyword #{kw.inspect}" }
    else
      { "key" => "excluded", "points" => 0, "max" => 100, "note" => "Excluded country #{@posting.client_country}" }
    end
  end

  # Multi-word skills are worth more than single words: "ruby on rails" is a
  # far stronger signal than "ruby".
  def skill_component
    hits = @career.skill_terms.select { |t| t.length > 2 && TextMatch.includes?(haystack, t) }
    return [ 0.0, "No skill match" ] if hits.empty?

    weighted = hits.sum { |t| t.include?(" ") ? 2.0 : 1.0 }
    fraction = [ weighted / 10.0, 1.0 ].min
    [ fraction, "Matched #{hits.take(6).join(', ')}#{hits.size > 6 ? " +#{hits.size - 6} more" : ''}" ]
  end

  def project_component
    hits = @career.project_terms.select { |t| t.length > 4 && TextMatch.includes?(haystack, t) }
    return [ 0.0, "No project-tag match" ] if hits.empty?

    fraction = [ hits.size / 6.0, 1.0 ].min
    [ fraction, "Overlaps past work: #{hits.take(5).join(', ')}" ]
  end

  def budget_component
    floor = @search.min_hourly&.to_f
    top   = @posting.hourly_max&.to_f || @posting.hourly_min&.to_f

    if @posting.fixed_amount.present?
      amount = @posting.fixed_amount.to_f
      min_fixed = (@search.min_fixed.presence || DEFAULT_MIN_FIXED).to_f
      return [ 1.0, "Fixed $#{amount.to_i}" ] if amount >= min_fixed
      return [ 0.25, "Fixed $#{amount.to_i}, under your $#{min_fixed.to_i} floor" ] if amount >= min_fixed / 2
      return [ 0.0, "Fixed $#{amount.to_i}, far under your $#{min_fixed.to_i} floor" ]
    end

    return [ 0.5, "Budget not stated" ] if top.blank? || top.zero?
    return [ 0.4, "Tops out at $#{top.to_i}/hr, under your $#{floor.to_i} floor" ] if floor && top < floor

    [ 1.0, "Pays up to $#{top.to_i}/hr" ]
  end

  def client_component
    score = 0.0
    notes = []

    if @posting.client_payment_verified
      score += 0.35
      notes << "payment verified"
    elsif !@posting.client_payment_verified.nil?
      notes << "UNVERIFIED payment"
    end

    spent = @posting.client_total_spent.to_f
    if spent >= 50_000 then score += 0.3; notes << "$#{(spent / 1000).round}k spent"
    elsif spent >= 5_000 then score += 0.2; notes << "$#{(spent / 1000).round}k spent"
    elsif spent.positive? then score += 0.1; notes << "$#{spent.to_i} spent"
    else notes << "no spend history"
    end

    hires = @posting.client_total_hires.to_i
    if hires >= 10 then score += 0.2; notes << "#{hires} hires"
    elsif hires.positive? then score += 0.1; notes << "#{hires} hires"
    end

    rating = @posting.client_rating.to_f
    if rating >= 4.5
      score += 0.15
      notes << "#{rating.round(1)}★"
    end

    [ [ score, 1.0 ].min, notes.join(", ").presence || "No client history" ]
  end

  # Being early is most of the advantage against 20 to 50 competing proposals.
  def recency_component
    return [ 0.5, "Publish time unknown" ] if @posting.published_at.blank?

    hours = (Time.current - @posting.published_at) / 3600.0
    return [ 1.0,  "Posted #{(hours * 60).round}m ago" ] if hours < 1
    return [ 0.75, "Posted #{hours.round}h ago" ] if hours < 6
    return [ 0.4,  "Posted #{hours.round}h ago" ] if hours < 24
    [ 0.1, "Posted #{(hours / 24).round}d ago" ]
  end
end
