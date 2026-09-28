module JobSource
  # Calls Upwork's GraphQL API. Every field and filter key below was verified
  # against the live API on 2026-09-08; see docs/upwork-schema.md.
  #
  # One combined query covers every saved search. BestSearchFor assigns each
  # posting to the right search locally, so per-search API calls buy nothing.
  # At the observed rate of 0.4 postings a minute, a 50-result page reaches back
  # about two hours, which is 40x the headroom a 3 minute cycle needs.
  class Live
    SEARCH = <<~GQL.freeze
      query RadarSearch(
        $filter: MarketplaceJobPostingsSearchFilter
        $searchType: MarketplaceJobPostingSearchType
        $sortAttributes: [MarketplaceJobPostingSearchSortAttribute]
      ) {
        marketplaceJobPostingsSearch(
          marketPlaceJobFilter: $filter
          searchType: $searchType
          sortAttributes: $sortAttributes
        ) {
          totalCount
          edges {
            node {
              id ciphertext title description
              publishedDateTime createdDateTime
              totalApplicants applied premium enterprise
              category subcategory experienceLevel
              engagement durationLabel freelancersToHire
              preferredFreelancerLocation preferredFreelancerLocationMandatory
              hourlyBudgetType
              hourlyBudgetMin { rawValue currency }
              hourlyBudgetMax { rawValue currency }
              amount { rawValue currency }
              skills { name prettyName }
              client {
                totalHires totalPostedJobs totalReviews totalFeedback
                verificationStatus hasFinancialPrivacy lastContractTitle
                totalSpent { rawValue currency }
                location { country city timezone }
              }
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    GQL

    # Screening questions live on the detail type, not the search result. Only
    # the fields below are within our granted scopes; asking for bid stats or
    # minJobSuccessScore fails the whole query.
    DETAIL = <<~GQL.freeze
      query RadarDetail($id: ID!) {
        marketplaceJobPosting(id: $id) {
          id
          contractTerms { contractType }
          contractorSelection {
            proposalRequirement { coverLetterRequired screeningQuestions { question sequenceNumber } }
            location { countries }
          }
        }
      }
    GQL

    def initialize(client: Upwork::Client.new)
      @client = client
    end

    # Upwork rejects a searchExpression longer than roughly 340 characters with
    # "Underling search failed", verified by bisection on 2026-09-08.
    MAX_EXPRESSION = 320

    def search_all(searches, first: Radar.page_size)
      expression_buckets(searches).flat_map { |expression| fetch(expression, first) }.uniq { |r| r["upwork_id"] }
    end

    def fetch(expression, first)
      data = @client.query(SEARCH, {
        "filter" => {
          "searchExpression_eq" => expression,
          "pagination_eq" => { "first" => first, "after" => "0" }
        },
        "searchType" => "USER_JOBS_SEARCH",
        "sortAttributes" => [ { "field" => "RECENCY" } ]
      })
      ApiUsage.record!
      Array(data.dig("marketplaceJobPostingsSearch", "edges")).filter_map { |e| normalize(e["node"]) }
    rescue Upwork::Error => e
      Rails.logger.error("[Upwork] search failed (#{expression.length} chars): #{e.message}")
      []
    end

    # One query per saved search, never merged.
    #
    # Merging them was cheaper but wrong. Results come back sorted by recency
    # across the whole OR, so a broad term like "web development" floods the
    # page with Shopify and Wix work and pushes the rare Rails posting out of
    # the window entirely. Losing a Rails job costs far more than an extra API
    # call, so each search gets its own feed and its own recency window.
    #
    # A single search whose terms exceed the length ceiling is split further.
    def expression_buckets(searches)
      Array(searches).flat_map { |search| pack(search.terms_list) }
    end

    def pack(terms)
      quoted = terms.map(&:strip).reject(&:blank?).uniq
                    .map { |t| t.include?(" ") ? %("#{t}") : t }

      quoted.each_with_object([]) do |term, buckets|
        if buckets.empty? || (buckets.last.length + 4 + term.length) > MAX_EXPRESSION
          buckets << term
        else
          buckets[-1] = "#{buckets.last} OR #{term}"
        end
      end
    end

    # Fetched only when we are about to write a proposal, so it costs one call
    # per job we actually care about rather than one per job we see.
    def detail(upwork_id)
      data = @client.query(DETAIL, { "id" => upwork_id })
      ApiUsage.record!
      node = data["marketplaceJobPosting"] or return {}

      requirement = node.dig("contractorSelection", "proposalRequirement") || {}
      {
        "contract_type" => node.dig("contractTerms", "contractType"),
        "cover_letter_required" => requirement["coverLetterRequired"],
        "screening_questions" => Array(requirement["screeningQuestions"])
                                   .sort_by { |q| q["sequenceNumber"].to_i }
                                   .filter_map { |q| q["question"].presence },
        "preferred_locations" => Array(node.dig("contractorSelection", "location", "countries")),
        "detail_fetched_at" => Time.current
      }
    end

    private

    def money(node, key)
      raw = node.dig(key, "rawValue")
      return nil if raw.blank?

      value = raw.to_f
      value.positive? ? value : nil
    end

    def normalize(node)
      return nil if node.blank? || node["id"].blank?

      fixed = money(node, "amount")
      hourly_min = money(node, "hourlyBudgetMin")
      hourly_max = money(node, "hourlyBudgetMax")

      {
        "upwork_id" => node["id"],
        "ciphertext" => node["ciphertext"],
        "title" => node["title"],
        "description" => node["description"],
        # There is no contractType on the search result. A positive fixed
        # amount means fixed price; otherwise it is hourly.
        "contract_type" => fixed ? "FIXED" : "HOURLY",
        "hourly_min" => hourly_min,
        "hourly_max" => hourly_max,
        "fixed_amount" => fixed,
        "total_applicants" => node["totalApplicants"],
        "already_applied" => !!node["applied"],
        "premium" => !!node["premium"],
        "enterprise" => !!node["enterprise"],
        "category" => node["category"],
        "subcategory" => node["subcategory"],
        "experience_level" => node["experienceLevel"],
        "engagement" => node["engagement"],
        "duration_label" => node["durationLabel"],
        "freelancers_to_hire" => node["freelancersToHire"],
        "preferred_locations" => Array(node["preferredFreelancerLocation"]),
        "preferred_location_mandatory" => !!node["preferredFreelancerLocationMandatory"],
        "client_country" => node.dig("client", "location", "country"),
        "client_city" => node.dig("client", "location", "city"),
        "client_timezone" => node.dig("client", "location", "timezone"),
        "client_total_posted_jobs" => node.dig("client", "totalPostedJobs"),
        "client_total_reviews" => node.dig("client", "totalReviews"),
        "client_last_contract_title" => node.dig("client", "lastContractTitle"),
        "client_financial_privacy" => node.dig("client", "hasFinancialPrivacy"),
        "client_payment_verified" => node.dig("client", "verificationStatus").to_s.casecmp?("VERIFIED"),
        "client_total_spent" => node.dig("client", "totalSpent", "rawValue").to_f,
        "client_total_hires" => node.dig("client", "totalHires"),
        "client_rating" => node.dig("client", "totalFeedback"),
        "skills" => Array(node["skills"]).filter_map { |s| s["prettyName"].presence || s["name"].presence },
        "published_at" => node["publishedDateTime"],
        "job_url" => node["ciphertext"].present? ? "https://www.upwork.com/jobs/#{node['ciphertext']}" : nil,
        "raw_payload" => node
      }
    end
  end
end
