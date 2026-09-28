# What a search would actually bring in, measured against live Upwork before
# it is saved.
#
# Thresholds are the hardest thing to set blind. This runs the search's words
# once, scores the latest results exactly as the poller would, and says how
# many jobs a day match, how many would reach the inbox, and how many would
# interrupt. One or two API calls.
class SearchPreview
  Result = Struct.new(:ok, :seen, :per_day, :inbox, :hot, :examples, :error, keyword_init: true) do
    def ok? = ok
  end

  SAMPLE = 50

  def self.call(...) = new(...).call

  def initialize(search)
    @search = search
  end

  def call
    live = JobSource::Live.new
    buckets = live.pack(@search.terms_list)
    return Result.new(ok: false, error: "Add at least one word to look for.") if buckets.empty?

    rows = buckets.first(2).flat_map { |expression| fetch(live, expression) }.uniq { |r| r["upwork_id"] }
    return Result.new(ok: true, seen: 0, per_day: 0, inbox: 0, hot: 0, examples: []) if rows.empty?

    scored = rows.map { |row|
      posting = JobPosting.new(row.slice(*JobPosting.column_names).except("id"))
      [ posting, ScoreJobPosting.call(posting, saved_search: @search).score ]
    }
    inbox = scored.select { |_, s| s >= @search.threshold.to_i }
    hot = scored.select { |_, s| s >= @search.hot_threshold.to_i }

    Result.new(ok: true, seen: rows.size, per_day: per_day(rows), inbox: inbox.size, hot: hot.size,
               examples: scored.sort_by { |_, s| -s }.first(5).map { |p, s| { title: p.title, score: s, budget: p.budget_label } })
  rescue Upwork::Error => e
    Result.new(ok: false, error: UpworkProbe.explain(e.message))
  end

  private

  def fetch(live, expression)
    data = Upwork::Client.new.query(JobSource::Live::SEARCH, {
      "filter" => { "searchExpression_eq" => expression, "pagination_eq" => { "first" => SAMPLE, "after" => "0" } },
      "searchType" => "USER_JOBS_SEARCH",
      "sortAttributes" => [ { "field" => "RECENCY" } ]
    })
    ApiUsage.record!
    Array(data.dig("marketplaceJobPostingsSearch", "edges")).filter_map { |e| live.send(:normalize, e["node"]) }
  end

  # How often these words match, from the time the latest results span.
  def per_day(rows)
    times = rows.filter_map { |r| Time.zone.parse(r["published_at"].to_s) rescue nil }
    return rows.size if times.size < 2

    hours = [ (Time.current - times.min) / 3600.0, 1 ].max
    ((rows.size / hours) * 24).round
  end
end
