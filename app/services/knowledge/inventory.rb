module Knowledge
  # Everything the history of one repository says about the person's part in
  # it. Deterministic, no model, no network.
  #
  # The distinction that matters is theirs versus everyone's. A README
  # describes what the team built; only the commit authors say what this person
  # did, which is the difference between a proposal that is true and one that
  # claims a colleague's work.
  class Inventory
    # Changes to these say nothing about what someone built.
    NOISE = %r{
      (\A|/)(node_modules|vendor|dist|build|coverage|public/assets|public/packs|tmp|log)/ |
      \.(lock|min\.js|min\.css|map|snap|svg|png|jpe?g|gif|ico|woff2?|ttf|pdf)\z |
      (\A|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Gemfile\.lock|poetry\.lock|composer\.lock)\z |
      (\A|/)db/(schema\.rb|structure\.sql)\z
    }x

    def self.call(...) = new(...).call

    def initialize(repo, scan)
      @repo = repo
      @scan = scan
      @path = repo.path
    end

    def call
      key = inventory_key
      return @repo if key.present? && key == @repo.inventory_key

      commits = log
      own = commits.select { |c| @scan.own?(c[:email], c[:name]) && !c[:merge] }
      churn = numstat

      @repo.update!(
        head_sha: head,
        total_commits: commits.size,
        own_commits: own.size,
        first_at: commits.map { |c| c[:at] }.min,
        last_at: commits.map { |c| c[:at] }.max,
        first_own_at: own.map { |c| c[:at] }.min,
        last_own_at: own.map { |c| c[:at] }.max,
        active_months: own.map { |c| c[:at].strftime("%Y-%m") }.uniq.size,
        lines_added: churn[:added],
        lines_removed: churn[:removed],
        top_dirs: churn[:dirs],
        top_files: churn[:files],
        file_count: Git.run(@path, "ls-files", "-z", timeout: 30).to_s.count("\0"),
        remote_url: Git.run(@path, "config", "--get", "remote.origin.url", timeout: 5).to_s.strip.presence,
        readme_head: readme,
        stack: StackDetector.call(@path),
        tables: tables,
        inventory_key: key,
        error: nil
      )
      @repo
    rescue StandardError => e
      Rails.logger.warn("[Knowledge::Inventory] #{@path}: #{e.class}: #{e.message}")
      @repo.update_columns(error: "#{e.class}: #{e.message}".first(500))
      @repo
    end

    # A repo is re-read only when its history or the claimed identities
    # changed, so a rescan of two hundred repos costs seconds.
    def inventory_key
      sha = head
      return nil if sha.blank?

      Digest::SHA1.hexdigest([ sha, @scan.identity_emails.sort, @scan.identity_names.sort ].join("|"))
    end

    def head = @head ||= Git.run(@path, "rev-parse", "HEAD", timeout: 5).to_s.strip.presence

    SEP = "\x1f".freeze

    def log
      out = Git.run(@path, "log", "--all", "--format=%ae#{SEP}%an#{SEP}%at#{SEP}%P", timeout: 90).to_s
      out.lines.filter_map { |line|
        email, name, at, parents = line.chomp.split(SEP, 4)
        next if at.blank?

        { email: email.to_s.downcase, name: name.to_s, at: Time.zone.at(at.to_i), merge: parents.to_s.split.size > 1 }
      }
    end

    # Lines they added and removed, and where: which directories and files they
    # actually worked in. That is what points the write-up at the right code.
    def numstat
      args = [ "log", "--all", "--no-merges", "--numstat", "--format=#{SEP}%ae#{SEP}%an" ]
      out = Git.run(@path, *args, timeout: 120).to_s

      added = removed = 0
      dirs = Hash.new(0)
      files = Hash.new(0)
      mine = false

      out.each_line do |line|
        line = line.chomp
        if line.start_with?(SEP)
          _, email, name = line.split(SEP, 3)
          mine = @scan.own?(email, name)
          next
        end
        next unless mine

        a, r, file = line.split("\t", 3)
        next if file.blank? || a == "-" || file.match?(NOISE)

        file = renamed(file) if file.include?(" => ")
        change = a.to_i + r.to_i
        added += a.to_i
        removed += r.to_i
        files[file] += change
        dirs[area(file)] += change
      end

      { added: added, removed: removed,
        dirs: dirs.sort_by { |_, v| -v }.first(12).to_h,
        files: files.sort_by { |_, v| -v }.first(20).map(&:first) }
    end

    # Git reports a move as "app/{old => new}/x.rb" or as "old => new".
    # Credit goes to where the file lives now.
    def renamed(file)
      return file.split(" => ", 2).last unless file.include?("{")

      file.sub(/\{[^}]* => ([^}]*)\}/, '\1').gsub(%r{/+}, "/")
    end

    # "app/services/billing/charge.rb" is billing work; two levels says that
    # where one ("app") says nothing.
    def area(file)
      parts = file.split("/")
      return parts.first if parts.size <= 2

      parts.first(2).join("/")
    end

    def readme
      file = Dir[File.join(@path, "{README,readme,Readme}{.md,.markdown,.txt,}")].first
      return nil unless file

      text = File.read(file, 6000).to_s.force_encoding(Encoding::UTF_8).scrub
      text = text.gsub(/!\[[^\]]*\]\([^)]*\)/, "")       # images and badges
                 .gsub(/\[!\[.*?\]\(.*?\)\]\(.*?\)/, "")
                 .gsub(/<[^>]+>/, "")
                 .gsub(/\n{3,}/, "\n\n").strip
      text.first(900).presence
    rescue StandardError
      nil
    end

    # The domain's nouns: invoices, appointments, parcels. A table list says
    # what a system is about faster than any README.
    def tables
      names = []
      schema = File.join(@path, "db", "schema.rb")
      names += File.read(schema).scan(/create_table "([^"]+)"/).flatten if File.exist?(schema)
      structure = File.join(@path, "db", "structure.sql")
      names += File.read(structure).scan(/CREATE TABLE (?:public\.)?"?(\w+)"?/i).flatten if File.exist?(structure)
      Dir[File.join(@path, "{,*/}prisma/schema.prisma")].first(2).each { |f| names += File.read(f).scan(/^model (\w+)/).flatten }
      names.reject { |n| n.start_with?("ar_internal", "schema_migrations", "active_storage", "solid_", "good_job") }.uniq.first(80)
    rescue StandardError
      []
    end
  end
end
