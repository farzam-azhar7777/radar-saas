class PassReason
  NEAR_MISS = 5

  attr_reader :kind, :headline, :factors, :gap

  def self.for(posting) = new(posting)

  def initialize(posting)
    @posting = posting
    reasons = Array(posting.score_reasons)
    limit = reasons.find { |r| r["key"] == "outside_limits" }
    search = posting.saved_search
    @factors = []

    if limit
      @kind, @headline = "limits", "Outside your job limits: #{limit['note']}"
    elsif posting.reposted_too_often?
      @kind, @headline = "reposted", posting.repost_note
    elsif posting.location_blocked?
      @kind, @headline = "location", "The client only hires from #{posting.location_label}."
    else
      @kind = "score"
      @gap = search ? search.threshold - posting.score.to_i : nil
      @headline = search ? "Scored #{posting.score}, #{@gap} under the #{search.name} search's inbox line of #{search.threshold}." : "Scored #{posting.score}."
      @factors = reasons.reject { |r| r["key"].in?(%w[outside_limits reposted]) }
                        .sort_by { |r| r["points"].to_i - r["max"].to_i }
                        .select { |r| r["max"].to_i - r["points"].to_i >= 5 }.first(2)
    end
  end

  def near_miss? = kind == "score" && gap.to_i.between?(1, NEAR_MISS)

  def to_h
    { "kind" => kind, "headline" => headline, "score" => @posting.score, "search_id" => @posting.saved_search_id,
      "threshold" => @posting.saved_search&.threshold, "gap" => gap }.compact
  end
end
