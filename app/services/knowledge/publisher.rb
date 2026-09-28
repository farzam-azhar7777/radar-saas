module Knowledge
  # Accepted projects, written into the career folder.
  #
  # Rebuilds everything that is derived: each project file, the index that job
  # matching reads, and skills.yml. Rebuilding from the accepted set each time
  # means the folder can never drift from what the person approved: take a
  # project back out and every trace of it goes with it.
  module Publisher
    # Tags are load-bearing for matching, so "Ruby on Rails", "rails" and
    # "ror" must be one tag, not three that each match a third of the jobs.
    TAG_ALIASES = {
      "ruby-on-rails" => "rails", "ror" => "rails", "rubyonrails" => "rails",
      "next-js" => "nextjs", "next" => "nextjs", "react-js" => "react", "reactjs" => "react",
      "node-js" => "nodejs", "node" => "nodejs", "postgres" => "postgresql", "psql" => "postgresql",
      "vue-js" => "vue", "vuejs" => "vue", "typescript-js" => "typescript", "ts" => "typescript",
      "multitenant" => "multi-tenant", "multi-tenancy" => "multi-tenant", "saas-platform" => "saas",
      "ai" => "ai-integration", "llm" => "llms", "gpt" => "openai"
    }.freeze

    module_function

    def call
      accepted = Project.accepted.includes(:repos).order(:position, :name).to_a

      keep = accepted.map(&:file)
      (CareerFolder.project_files - keep).each { |f| CareerFolder.remove_project!(f) }

      entries = accepted.map do |project|
        data = project.draft.except("open_questions")
        CareerFolder.write_project!(project.file, data.to_yaml.delete_prefix("---\n"))
        project.update_columns(own_commits_when_written: project.own_commits) if project.own_commits_when_written.nil?
        data.slice("name", "one_liner", "tags", "relevance", "period", "role").merge("file" => project.file)
      end

      CareerFolder.write_index!(entries)
      CareerFolder.write_skills!(skills(accepted))
      CareerData.reload!
    end

    # Short and flat. A tag is a word or three, never a sentence: matching
    # looks for it inside job posts, and "admin-panels-and-internal-dashboards"
    # will never appear in one.
    def normalize_tags(list)
      Array(list).map { |t| t.to_s.gsub(/\([^)]*\)/, "") }
                 .flat_map { |t| t.split(/[,;\/]/) }
                 .map { |t| t.downcase.strip.gsub(/[^a-z0-9.+#]+/, "-").gsub(/\A-|-\z/, "").delete(".") }
                 .map { |t| TAG_ALIASES.fetch(t, t) }
                 .reject { |t| t.blank? || t.count("-") > 2 || t.length > 32 }
                 .uniq.first(14)
    end

    def tag_vocabulary
      Project.accepted.flat_map { |p| Array(p.draft["tags"]) + Array(p.draft["relevance"]) }.tally
             .sort_by { |_, n| -n }.map(&:first)
    end

    # Every tool across accepted projects, weighted by the person's own
    # commits, each with the evidence behind it. What they typed in their
    # profile is kept too, so skipping the scan never leaves this empty.
    def skills(accepted)
      tally = Hash.new { |h, k| h[k] = { "group" => k[0], "projects" => 0, "commits" => 0, "versions" => [], "years" => [] } }

      accepted.each do |project|
        repo_stack(project).each do |group, labels|
          labels.each do |label|
            base, version = split_version(label)
            entry = tally[[ group, base ]]
            entry["projects"] += 1
            entry["commits"] += project.own_commits.to_i
            entry["versions"] |= [ version ] if version
            entry["years"] |= [ project.first_at&.year, project.last_at&.year ].compact
          end
        end
      end

      groups = Hash.new { |h, k| h[k] = [] }
      tally.sort_by { |(_, _), e| [ -e["commits"], -e["projects"] ] }.each do |(group, name), e|
        groups[group] << {
          "name" => name,
          "versions" => e["versions"].sort_by { |v| Gem::Version.new(v) rescue 0 }.presence,
          "evidence" => evidence_line(e)
        }.compact
      end

      declared = Profile.current.skills_list.reject { |s| groups.values.flatten.any? { |e| e["name"].casecmp?(s) } }
      groups["declared"] = declared.map { |s| { "name" => s, "evidence" => "from your profile" } } if declared.any?

      StackDetector::GROUPS.filter_map { |g| [ g, groups[g] ] if groups[g].present? }.to_h
                           .merge(groups.slice("other", "declared"))
    end

    # Manual projects have no repos, so their stack comes from what was typed.
    def repo_stack(project)
      stack = project.stack
      return stack if stack.present?

      { "other" => Array(project.draft["stack"]).map(&:to_s) }
    end

    def split_version(label)
      m = label.to_s.match(/\A(.+?) (\d+(?:\.\d+)?)\z/)
      m ? [ m[1], m[2] ] : [ label.to_s, nil ]
    end

    def evidence_line(e)
      years = e["years"].minmax.uniq.join("-")
      parts = [ "#{e['projects']} #{'project'.pluralize(e['projects'])}" ]
      parts << years if years.present?
      parts << "#{e['commits']} of your commits" if e["commits"].positive?
      parts.join(", ")
    end
  end
end
