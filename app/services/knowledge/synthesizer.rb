module Knowledge
  # Writes one project up for the career folder, from evidence only.
  #
  # Runs read-only inside the project's own repositories, so it may open the
  # files the person changed most, and nothing it writes reaches disk except
  # through Publisher after they accept it.
  #
  # Two fields are never the model's to decide. The name is what the person
  # confirmed during curation: a repo name in the career files once caused ten
  # of eleven proposals to cite a product by the wrong name. The period comes
  # from their commit dates.
  class Synthesizer
    class Error < StandardError; end

    TIMEOUT = Integer(ENV.fetch("RADAR_KNOWLEDGE_TIMEOUT", 600))

    FIELDS = %w[name role client period status url one_liner stack domain team_size
                your_scope highlights challenges_solved tags relevance commits open_questions].freeze

    Result = Struct.new(:yaml, :questions, :meta, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(project)
      @project = project
    end

    def call
      repos = @project.repos.to_a
      raise Error, "this project has no repositories to read" if repos.empty?

      result = ClaudeRun.call(prompt, timeout: TIMEOUT, model: Radar.writer_model, label: "project write-up",
                              chdir: repos.first.path, add_dirs: repos.drop(1).map(&:path))
      data = parse(ClaudeRun.fenced(result.text))
      Result.new(yaml: dump(data), questions: Array(data["open_questions"]).map(&:to_s).reject(&:blank?),
                 meta: result.meta.merge("duration_ms" => result.duration_ms))
    rescue ClaudeRun::Error => e
      raise Error, e.message
    end

    def prompt
      name = Profile.first_name
      <<~TXT
        You are writing up ONE project from #{name}'s work history for a career file. An Upwork
        proposal writer will quote from it, word for word, to real clients. A false line here
        becomes a false claim in front of a client, so accuracy beats impressiveness every time.

        Below is the evidence Radar gathered from the git history. The commit messages are
        #{name}'s own and are the only record of what #{name} personally did. The README and
        table names describe the product, which a whole team may have built. Scope every claim
        about #{name}'s work to what their commits show.

        You MAY open up to 8 files from "Files they changed most" to understand what the code
        does. Do not explore beyond that; everything else you need is below.

        #{Evidence.call(@project)}

        ---
        #{feedback_block}
        WRITE THE PROJECT FILE. Output ONLY one fenced ```yaml block with exactly these keys:

        name: "#{@project.name}"          # exactly this, it is the name #{name} confirmed
        role: ""                # e.g. "Lead backend developer", only if the commits support it
        client: ""              # only if the evidence names one; never guess from a folder name
        period: "#{@project.span_label}"   # exactly this
        status: ""              # shipped / in production / MVP / shelved, only if evident
        url: ""                 # only a URL that appears in the evidence
        one_liner: ""           # one sentence: what it is and who it is for
        stack: []               # real tools from the evidence, with versions where given
        domain: ""              # healthcare / fintech / real estate / e-commerce ...
        team_size: ""           # only if the evidence shows it; otherwise leave empty
        your_scope: ""          # 2-3 sentences: what #{name} built, from their commits
        highlights: []          # 3 to 6 bullets, each carrying a specific: a version, an
                                # integration, a table, a number from the evidence
        challenges_solved: []   # 1 to 4 hard problems visible in the commits
        tags: []                # 6 to 12 tools and domains, one to three words each,
                                # lowercase-hyphenated: rails, stripe, legal-tech
        relevance: []           # 3 to 8 kinds of job this speaks to, one to three words
                                # each: payments, multi-tenant, real-time, admin-panels
        commits: "#{@project.own_commits} of #{@project.total_commits}"   # exactly this
        open_questions: []      # what you could not determine that #{name} should fill in

        RULES
        - Never invent a client, a number, a user count, revenue, performance figures, a team
          size or a URL. The only numbers you may use are ones in the evidence.
        - Leave a field empty ("" or []) rather than guess, and add a short question to
          open_questions instead, e.g. "Who was the client?", "Is there a public URL?".
        - If the name above looks like a repository or folder name rather than a product a
          client would recognise, add "What do clients call this product?" to open_questions.
        - Reuse tags from this vocabulary where they fit before inventing new ones:
          #{Publisher.tag_vocabulary.first(120).join(', ').presence || '(none yet)'}
        - Hyphens, never em or en dashes. Plain, specific language. No buzzwords.
      TXT
    end

    def feedback_block
      return "" if @project.note.blank?

      "#{Profile.first_name} read the previous write-up and asked for this, apply it precisely:\n#{@project.note}\n\n" \
        "Previous write-up:\n#{@project.draft_yaml.to_s.first(4000)}\n\n---\n"
    end

    def parse(text)
      data = YAML.safe_load(text.to_s, permitted_classes: [ Date, Time ])
      raise Error, "the write-up was not a YAML mapping" unless data.is_a?(Hash)

      data
    rescue Psych::Exception => e
      raise Error, "the write-up was not valid YAML: #{e.message.first(200)}"
    end

    # Rewritten in the template's order, with the fixed fields forced and the
    # list fields cleaned, so every project file has the same shape.
    def dump(data)
      data = data.transform_keys(&:to_s)
      data["name"] = @project.name
      data["period"] = @project.span_label
      data["commits"] = "#{@project.own_commits} of #{@project.total_commits}"
      data["client"] = @project.client if @project.client.present?
      data["url"] = @project.url if @project.url.present?
      data["tags"] = Publisher.normalize_tags(data["tags"])
      data["relevance"] = Publisher.normalize_tags(data["relevance"])
      %w[stack highlights challenges_solved open_questions].each do |k|
        data[k] = Array(data[k]).map { |v| plain(v) }.reject(&:blank?)
      end
      %w[role client status url one_liner domain your_scope].each { |k| data[k] = plain(data[k]) }
      data["team_size"] = data["team_size"].to_s.strip.presence

      FIELDS.to_h { |k| [ k, data[k] ] }.reject { |_, v| v.blank? }.to_yaml.delete_prefix("---\n")
    end

    def plain(value) = value.to_s.gsub(/\s*[—–]\s*/, " - ").strip
  end
end
