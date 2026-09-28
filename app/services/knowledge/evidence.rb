module Knowledge
  # Everything the writer is allowed to know about one project, bounded.
  #
  # The writer does not explore. A repository with 7,000 files cannot be read,
  # and a model left to sample it writes up whatever it happened to open. So
  # the facts are gathered here, deterministically, and handed over: the
  # person's own commit subjects, where they worked, what it is built with,
  # and numbers that are true by construction.
  class Evidence
    SUBJECT_LIMIT = 220
    CHAR_LIMIT = 22_000

    def self.call(...) = new(...).call

    def initialize(project, scan: project.scan)
      @project = project
      @scan = scan
    end

    def call
      parts = [ header ]
      @project.repos.each { |repo| parts << repo_section(repo) }
      parts << subjects_section
      parts.compact.join("\n\n").first(CHAR_LIMIT)
    end

    def header
      lines = [ "PROJECT: #{@project.name}" ]
      lines << "Client as the person named it: #{@project.client}" if @project.client.present?
      lines << "Public URL as the person gave it: #{@project.url}" if @project.url.present?
      lines << "Their commits: #{@project.own_commits} of #{@project.total_commits} across #{@project.repos.size} " \
               "#{'repository'.pluralize(@project.repos.size)} (#{@project.share}%)."
      lines << "Their active period: #{@project.span_label} (first #{@project.first_at&.to_date}, last #{@project.last_at&.to_date})."
      lines.join("\n")
    end

    def repo_section(repo)
      lines = [ "--- repository: #{repo.name} ---" ]
      lines << "Remote: #{repo.remote_url}" if repo.remote_url.present?
      lines << "Their commits: #{repo.own_commits} of #{repo.total_commits}. Lines they added: #{repo.lines_added}, removed: #{repo.lines_removed}. " \
               "Months active: #{repo.active_months}. Files in repo: #{repo.file_count}."
      (repo.stack || {}).each { |group, names| lines << "#{group.capitalize}: #{Array(names).join(', ')}" if Array(names).any? }
      lines << "Database tables: #{Array(repo.tables).first(60).join(', ')}" if Array(repo.tables).any?
      if (dirs = repo.top_dirs).present?
        lines << "Where they worked (lines changed): " + dirs.map { |d, n| "#{d} #{n}" }.join(", ")
      end
      lines << "Files they changed most: #{Array(repo.top_files).first(15).join(', ')}" if Array(repo.top_files).any?
      lines << "README opening:\n#{repo.readme_head}" if repo.readme_head.present?
      lines.join("\n")
    end

    # Their own commit messages are the one source that says what THEY did.
    # Deduplicated, trivia dropped, sampled evenly across time so a project's
    # first year is not drowned by its last.
    def subjects_section
      all = @project.repos.flat_map { |r| subjects(r) }
      return nil if all.empty?

      all = all.uniq { |s| s[:text].downcase.gsub(/\W+/, " ").strip }.sort_by { |s| s[:at] }
      picked = sample(all, SUBJECT_LIMIT)
      "--- their commit messages (#{picked.size} of #{all.size} distinct, oldest first) ---\n" +
        picked.map { |s| "#{s[:at].strftime('%Y-%m')}  #{s[:text]}" }.join("\n")
    end

    SEP = "\x1f".freeze
    TRIVIAL = /\A(wip|fix|fixes|fixed|update|updates|updated|changes|minor|test|tests|merge|cleanup|refactor|temp|tmp|\.|-|typo|lint|format|rubocop)\W*\z/i

    def subjects(repo)
      out = Git.run(repo.path, "log", "--all", "--no-merges", "--format=%ae#{SEP}%an#{SEP}%at#{SEP}%s", timeout: 60).to_s
      out.lines.filter_map { |line|
        email, name, at, text = line.chomp.split(SEP, 4)
        next unless @scan.own?(email, name)

        text = text.to_s.strip.sub(/\s*\(#\d+\)\z/, "")
        next if text.split.size < 3 || text.match?(TRIVIAL) || text.start_with?("Merge ", "Revert \"Merge")

        { at: Time.zone.at(at.to_i), text: text.first(160) }
      }
    end

    def sample(list, n)
      return list if list.size <= n

      step = list.size.to_f / n
      (0...n).map { |i| list[(i * step).floor] }
    end
  end
end
