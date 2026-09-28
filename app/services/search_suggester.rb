# Proposes saved searches from what the person actually does.
#
# A search is words to look for plus two thresholds, and a new user has no
# feel for either. Claude reads their profile and projects and proposes a few,
# each with a reason; the person edits or drops them. With nothing to read, or
# if Claude fails, the preset catalogue is offered instead.
module SearchSuggester
  STATE = "setup.search_suggestions".freeze
  TIMEOUT = 240

  Suggestion = Struct.new(:name, :terms, :threshold, :hot_threshold, :auto_generate, :template_name,
                          :excluded_keywords, :reason, keyword_init: true)

  module_function

  def presets
    YAML.safe_load_file(Rails.root.join("config", "search_presets.yml")).map { |p|
      Suggestion.new(name: p["name"], terms: p["terms"], threshold: 70, hot_threshold: 80,
                     auto_generate: false, template_name: "personalised-skills-for-job", excluded_keywords: [])
    }
  end

  # The saved state, for the page: { "status" => running|ready|failed, "items" => [...], "error" => }
  def state
    JSON.parse(Setting.get(STATE, "{}"))
  rescue JSON::ParserError
    {}
  end

  def items = Array(state["items"]).map { |h| Suggestion.new(**h.symbolize_keys.slice(*Suggestion.members)) }

  def running? = state["status"] == "running" && Time.zone.parse(state["at"].to_s).to_i > 10.minutes.ago.to_i

  def start!
    save("status" => "running", "at" => Time.current.iso8601, "items" => state["items"])
    SuggestSearchesJob.perform_later
  end

  def call
    items = parse(ClaudeRun.fenced(ClaudeRun.call(prompt, timeout: TIMEOUT, label: "suggest searches").text))
    save("status" => "ready", "at" => Time.current.iso8601, "items" => items.map(&:to_h))
  rescue StandardError => e
    Rails.logger.error("[SearchSuggester] #{e.class}: #{e.message}")
    save("status" => "failed", "at" => Time.current.iso8601, "error" => e.message.first(300))
  end

  def save(hash) = Setting.set(STATE, hash.to_json)

  def prompt
    profile = Profile.current
    career = CareerData.instance
    projects = career.index_entries.first(25).map { |p|
      "- #{p['name']}: #{p['one_liner']} [#{Array(p['tags']).join(', ')}]"
    }
    projects = curated_projects if projects.empty?

    <<~TXT
      You are setting up Upwork job searches for #{profile.first_name}, a freelancer.

      Title: #{profile.title}
      Skills they want work for: #{profile.skills_list.join(', ')}
      Rate: #{profile.hourly_rate.present? ? "$#{profile.hourly_rate.to_i}/hr" : 'not given'}

      Their projects:
      #{projects.join("\n").presence || '(none recorded)'}

      Available proposal templates: #{career.templates.join(', ').presence || 'personalised-skills-for-job'}

      Propose 3 to 6 saved searches. Each one watches for one kind of job they are clearly qualified for.

      Rules:
      - terms are 3 to 8 short phrases a CLIENT would type in an Upwork job post, lowercase:
        "rails developer", "next.js", "stripe integration". Never a sentence. No quotes inside a term.
      - The terms of one search together stay under 300 characters.
      - Never one broad search with every skill: broad terms flood the results and bury the good jobs.
      - Order by how central the work is to them. The first one or two are their core work: set
        auto_generate true on those only. Everything else false (it notifies and waits).
      - threshold (0-100) decides the inbox: 65 to 75. hot_threshold decides an instant alert: equal to
        threshold for core searches, 80 to 85 for the rest so they cannot spam.
      - excluded_keywords: words that mark a job as not theirs even when the terms match, e.g.
        wordpress, shopify, wix for a custom-software developer. Leave empty if unsure.
      - reason: one plain sentence saying which of their projects or skills this search is built on.

      Output ONLY a JSON array in one fenced block:
      [{"name": "...", "terms": ["..."], "threshold": 70, "hot_threshold": 70, "auto_generate": true,
        "template_name": "personalised-skills-for-job", "excluded_keywords": [], "reason": "..."}]
    TXT
  end

  # Before any write-up is accepted, the chosen projects' stacks still say a
  # lot about what someone does.
  def curated_projects
    Knowledge::Project.where(included: true).ranked.limit(20).map { |p|
      "- #{p.name}: #{p.own_commits} commits, built with #{p.stack_names.first(8).join(', ')}"
    }
  end

  def parse(text)
    list = JSON.parse(text)
    raise ArgumentError, "expected a list of searches" unless list.is_a?(Array)

    templates = CareerData.instance.templates.presence ||
                YAML.safe_load_file(CareerFolder::SOURCE.join("templates", "_index.yml"))["templates"].map { |t| t["name"] }
    list.first(6).filter_map { |h|
      next unless h.is_a?(Hash) && h["name"].present?

      terms = Array(h["terms"]).map { |t| t.to_s.downcase.delete('"').strip }.reject(&:blank?).uniq.first(8)
      next if terms.empty?

      threshold = h["threshold"].to_i.clamp(50, 95)
      Suggestion.new(
        name: h["name"].to_s.strip.first(40), terms: terms, threshold: threshold,
        hot_threshold: [ h["hot_threshold"].to_i, threshold ].max.clamp(threshold, 100),
        auto_generate: h["auto_generate"] == true,
        template_name: templates.include?(h["template_name"]) ? h["template_name"] : templates.first,
        excluded_keywords: Array(h["excluded_keywords"]).map { |k| k.to_s.downcase.strip }.reject(&:blank?).first(10),
        reason: h["reason"].to_s.strip.first(240)
      )
    }
  end
end
