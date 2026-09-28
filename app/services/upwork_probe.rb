# One real search, to prove the connection works end to end, and to say
# plainly what is wrong when it does not. The poller swallows errors so one bad
# cycle cannot stop it; setup needs the opposite.
module UpworkProbe
  Result = Struct.new(:ok, :total, :titles, :error, keyword_init: true) do
    def ok? = ok
  end

  module_function

  def call(expression = "developer")
    data = Upwork::Client.new.query(JobSource::Live::SEARCH, {
      "filter" => { "searchExpression_eq" => expression, "pagination_eq" => { "first" => 5, "after" => "0" } },
      "searchType" => "USER_JOBS_SEARCH",
      "sortAttributes" => [ { "field" => "RECENCY" } ]
    })
    ApiUsage.record!
    search = data["marketplaceJobPostingsSearch"] || {}
    Result.new(ok: true, total: search["totalCount"],
               titles: Array(search["edges"]).filter_map { |e| e.dig("node", "title") })
  rescue Upwork::AuthError => e
    Result.new(ok: false, error: Upwork::TokenError.explain(e.message))
  rescue Upwork::Error => e
    Result.new(ok: false, error: explain(e.message))
  end

  # Upwork's messages, in terms of what to do about them.
  def explain(message)
    case message
    when /permission|scope|not authorized|forbidden/i
      "Upwork says this key lacks a permission Radar needs (#{message.first(160)}). Check that the key has " \
      "\"Read marketplace Job Postings\" ticked."
    else
      "Upwork returned an error: #{message.first(240)}"
    end
  end
end
