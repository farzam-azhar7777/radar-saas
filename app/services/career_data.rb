# Read-only view over the career folder. CareerFolder writes it during setup,
# and ApplicationArchiver adds to it on "Mark applied". Nothing else does.
class CareerData
  ALIASES = {
    "ruby on rails" => %w[rails ror ruby-on-rails],
    "hotwire (turbo + stimulus)" => %w[hotwire turbo stimulus],
    "next.js" => %w[nextjs next],
    "postgresql" => %w[postgres psql],
    "react native (expo)" => %w[react-native expo],
    "stripe (checkout, subscriptions, connect)" => %w[stripe],
    "ionic / angular" => %w[ionic angular]
  }.freeze

  # Rebuilt whenever a career file changes on disk. The setup wizard writes
  # these from the web process while the poller scores jobs in the worker
  # process, and a memo that never expired left the worker scoring against an
  # empty folder until someone restarted it.
  WATCHED = %w[profile.yml skills.yml projects/_index.yml templates/_index.yml].freeze

  def self.instance
    stamp = WATCHED.map { |f| File.mtime(Radar.career_path.join(f)).to_f rescue nil } + [ Radar.career_path.to_s ]
    @instance = nil if stamp != @stamp
    @stamp = stamp
    @instance ||= new
  end

  def self.reload!
    @instance = nil
    @stamp = nil
  end

  def root = Radar.career_path

  # Every skill name from skills.yml, lowercased, plus useful aliases.
  def skill_terms
    @skill_terms ||= begin
      path = root.join("skills.yml")
      return [] unless path.exist?

      raw = YAML.safe_load_file(path, permitted_classes: [ Date, Time ], aliases: true) || {}
      names = raw.values.flatten.filter_map { |e| e.is_a?(Hash) ? e["name"] : e }
      names.flat_map { |n|
        key = n.to_s.downcase.strip
        [ key, key.sub(/\s*\(.*\)\z/, "").strip ] + ALIASES.fetch(key, [])
      }.map(&:strip).reject(&:blank?).uniq
    end
  end

  # Tags and relevance markers across every project. These are load-bearing
  # for matching, per CLAUDE.md.
  def project_terms
    @project_terms ||= begin
      path = root.join("projects", "_index.yml")
      return [] unless path.exist?

      raw = YAML.safe_load_file(path, permitted_classes: [ Date, Time ], aliases: true) || {}
      Array(raw["projects"]).flat_map { |p|
        Array(p["tags"]) + Array(p["relevance"])
      }.map { |t| t.to_s.downcase.tr("-", " ").strip }.reject(&:blank?).uniq
    end
  end

  # The career files, verbatim, for inlining into a prompt.
  #
  # Telling the model to go and read these costs a tool call and a full round
  # trip each, and the planning call spent more than five minutes exploring the
  # repo before writing a word. Handing it the index up front leaves it only
  # the two or three individual project files it actually chose to open, which
  # is the part worth paying for.
  INLINE_LIMIT = 24_000

  def briefing
    @briefing ||= [
      file_section("profile.yml"),
      file_section("skills.yml"),
      file_section("projects/_index.yml")
    ].compact.join("\n\n")
  end

  # The projects most worth reading for THIS job, in full.
  #
  # Radar already knows which of his projects a posting overlaps; it scores
  # every job against their tags. Handing the planner those files removes the
  # last reason for it to go exploring the repo, which is what the planning
  # call was spending most of its time doing.
  RELEVANT_PROJECTS = 6

  def projects_for(posting)
    wanted = "#{posting.title} #{posting.description} #{Array(posting.skills).join(' ')}".downcase

    ranked = index_entries.map { |entry|
      terms = (Array(entry["tags"]) + Array(entry["relevance"])).map { |t| t.to_s.downcase.tr("-", " ") }
      [ entry, terms.count { |t| t.present? && wanted.include?(t) } ]
    }

    picked = ranked.sort_by { |_, score| -score }.first(RELEVANT_PROJECTS).select { |_, score| score.positive? }
    picked = ranked.first(3) if picked.empty?

    picked.filter_map { |entry, _| file_section("projects/#{entry['file']}") if entry["file"].present? }.join("\n\n")
  end

  def index_entries
    @index_entries ||= begin
      path = root.join("projects", "_index.yml")
      path.exist? ? Array(YAML.safe_load_file(path, permitted_classes: [ Date, Time ], aliases: true)&.dig("projects")) : []
    end
  rescue StandardError
    []
  end

  def file_section(relative)
    path = root.join(relative)
    return nil unless path.exist?

    "--- #{relative} ---\n#{path.read.truncate(INLINE_LIMIT)}"
  rescue StandardError
    nil
  end

  def templates
    path = root.join("templates", "_index.yml")
    return [] unless path.exist?

    raw = YAML.safe_load_file(path, permitted_classes: [ Date, Time ], aliases: true) || {}
    Array(raw["templates"]).map { |t| t["name"] }.compact
  end

  # A few real tool and library names from their own skills, most specific
  # groups first, for the spec's example of what "specific" means.
  SPECIFIC_GROUPS = %w[libraries integrations frameworks infra_and_tools infrastructure].freeze

  def example_tools(limit)
    path = root.join("skills.yml")
    return [] unless path.exist?

    raw = YAML.safe_load_file(path, permitted_classes: [ Date, Time ], aliases: true) || {}
    groups = SPECIFIC_GROUPS.filter_map { |g| raw[g] } + (raw.keys - SPECIFIC_GROUPS).map { |g| raw[g] }
    groups.flat_map { |g| Array(g) }
          .filter_map { |e| e.is_a?(Hash) ? e["name"] : e }
          .map(&:to_s).reject(&:blank?).uniq.first(limit)
  rescue StandardError
    []
  end

  def present?
    root.join("CLAUDE.md").exist?
  end
end
