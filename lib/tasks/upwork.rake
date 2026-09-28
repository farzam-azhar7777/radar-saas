namespace :upwork do
  desc "One-time OAuth2: print the consent URL, then take the pasted verifier code"
  task authorize: :environment do
    abort "Save your Upwork API key first, in the app's Setup (or Settings)." unless Upwork::Client.configured?

    puts "\n1. Open this URL and approve the app:\n\n   #{Upwork::Client.authorize_url}\n\n"
    print "2. Paste the verifier code from the redirect: "
    code = $stdin.gets.to_s.strip
    abort "No code given" if code.blank?

    Upwork::Client.new.exchange_code(code)
    puts "\nToken pair saved to storage/upwork_tokens.json (chmod 600)."
  end

  desc "Phase 3 task one: dump the real GraphQL schema and diff it against our assumptions"
  task introspect: :environment do
    query = <<~GQL
      query Introspect {
        __type(name: "MarketplaceJobPostingsSearchFilter") { inputFields { name type { name kind ofType { name } } } }
        node: __type(name: "MarketplaceJobPosting") { fields { name type { name kind ofType { name } } } }
      }
    GQL

    data = Upwork::Client.new.query(query)
    out = Rails.root.join("docs", "upwork-schema.json")
    File.write(out, JSON.pretty_generate(data))
    puts "Wrote #{out}"

    assumed = JobSource::Live::QUERY.scan(/^\s{14}(\w+)/).flatten.uniq
    actual  = Array(data.dig("node", "fields")).map { |f| f["name"] }
    puts "\nFields we select but the schema does NOT have:"
    puts((assumed - actual).map { |f| "  MISSING  #{f}" }.presence || [ "  none" ])
    puts "\nFilter inputs actually available:"
    Array(data.dig("__type", "inputFields")).each { |f| puts "  #{f['name']}" }
  end
end
