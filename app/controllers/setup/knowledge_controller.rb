module Setup
  # The "Your work" step: scan a folder, claim identities, choose projects,
  # review the write-ups. Every action returns straight away; the slow parts
  # run in jobs and the page refreshes itself as they land.
  class KnowledgeController < BaseController
    # Only the actions about the folder need one. A project added by hand, or
    # kept after choosing another folder, has no scan and must still be editable.
    before_action :set_scan, only: %i[restart rescan identities write merge]
    before_action :set_project, only: %i[update toggle exclude restore split accept unaccept rewrite]

    def scan
      path = File.expand_path(params[:root_path].to_s.strip.presence || "~")
      unless File.directory?(path)
        return go_to("knowledge", alert: "#{path} is not a folder on this computer. Paste the full path, for example ~/code.")
      end

      current = Knowledge::Scan.current
      forget(current) if current && current.root_path != path
      scan = Knowledge::Scan.find_or_initialize_by(root_path: path)
      scan.update!(status: "discovering", error: nil, progress_done: 0, progress_total: 0)
      Knowledge::DiscoverJob.perform_later(scan)
      go_to("knowledge")
    end

    # Starting over forgets the folder and every choice made about it.
    # Projects already accepted stay in the career folder; they can be taken
    # out one by one.
    def restart
      forget(@scan) if @scan
      go_to("knowledge", notice: "Cleared. Choose a folder to start again.")
    end

    # Re-reads everything, keeping every name, choice and exclusion.
    def rescan
      @scan.update!(status: "discovering", error: nil)
      Knowledge::DiscoverJob.perform_later(@scan)
      go_to("knowledge", notice: "Rescanning. Your choices are kept.")
    end

    def identities
      emails = Array(params[:emails]).map { |e| e.to_s.downcase.strip }.reject(&:blank?)
      return go_to("knowledge", alert: "Tick at least one of the identities that is you.") if emails.empty?

      names = @scan.candidates.select { |c| emails.include?(c["email"]) }.flat_map { |c| Array(c["names"]) }
      # A name shared by someone else would claim their commits too.
      shared = @scan.candidates.reject { |c| emails.include?(c["email"]) }.flat_map { |c| Array(c["names"]) }.map(&:downcase)
      @scan.update!(identities: emails, names: names.uniq.reject { |n| shared.include?(n.downcase) || n.split.size < 2 },
                    status: "inventorying")
      Knowledge::InventoryJob.perform_later(@scan)
      go_to("knowledge")
    end

    def write
      chosen = @scan.projects.where(included: true, status: %w[candidate failed])
      return go_to("knowledge", alert: "Tick at least one project to write up.") if chosen.none?

      chosen.find_each(&:queue!)
      @scan.update!(status: "writing")
      go_to("knowledge", notice: "Writing up #{chosen.count} #{'project'.pluralize(chosen.count)}. This page updates as each one lands.")
    end

    def toggle
      @project.update!(included: !@project.included)
      go_to_project
    end

    # Edits a project at any stage, accepted ones included. The name, client
    # and link can be changed in their own fields or inside the write-up;
    # whichever one the person actually changed wins, and all three are
    # written into the write-up, because that is the file proposals read.
    def update
      attrs = params.require(:project).permit(:name, :client, :url, :draft_yaml)
      data =
        if attrs.key?(:draft_yaml)
          YAML.safe_load(attrs[:draft_yaml].to_s, permitted_classes: [ Date, Time ]) rescue nil
        else
          @project.draft.presence
        end
      if attrs.key?(:draft_yaml) && !data.is_a?(Hash)
        return go_to_project(alert: "That is not valid YAML, so nothing was saved. Check the indentation.")
      end

      data = data.is_a?(Hash) ? data : nil
      name = changed(attrs, :name, data, @project.name) || @project.name
      client = changed(attrs, :client, data, @project.client)
      url = changed(attrs, :url, data, @project.url)
      changes = { name: name, client: client, url: url }

      if data
        data = data.merge("name" => name, "client" => client, "url" => url).compact_blank
        changes[:draft_yaml] = data.to_yaml.delete_prefix("---\n")
      end

      @project.update!(changes)
      if @project.status == "accepted"
        Knowledge::Publisher.call
        go_to_project(notice: "Saved. Proposals use the updated #{@project.name} from now on.")
      else
        go_to_project(notice: "Saved.")
      end
    end

    def exclude
      @project.exclude!
      go_to_project(notice: "#{@project.name} is left out, and stays out when you rescan.")
    end

    def restore
      @project.update!(status: @project.draft_yaml.present? ? "drafted" : "candidate", included: true)
      go_to_project
    end

    def merge
      ids = Array(params[:ids]).map(&:to_i)
      projects = @scan.projects.where(id: ids).ranked.to_a
      return go_to("knowledge", alert: "Tick two or more projects to merge.") if projects.size < 2

      keeper, *rest = projects
      rest.each do |p|
        p.repos.update_all(knowledge_project_id: keeper.id)
        p.destroy
      end
      keeper.update!(status: "candidate", included: true, draft_yaml: nil)
      Knowledge::Ranker.call(@scan)
      go_to_project(keeper, notice: "Merged into #{keeper.name}.")
    end

    # Moves one repository out into a project of its own.
    def split
      @scan = @project.scan
      repo = @project.repos.find(params[:repo_id])
      fresh = @scan.projects.create!(name: Knowledge::Clusterer.display_name([ repo ]),
                                     stem: "#{Knowledge::Clusterer.stem(repo.name)}-#{repo.id}", included: true)
      repo.update!(knowledge_project_id: fresh.id)
      Knowledge::Ranker.call(@scan)
      go_to_project(fresh, notice: "#{repo.name} is its own project now.")
    end

    def accept
      @project.accept!
      Onboarding.unskip!("knowledge")
      go_to_project(notice: "#{@project.name} is in your career folder. Proposals can cite it now.")
    end

    def unaccept
      @project.unaccept!
      go_to_project(notice: "#{@project.name} is out of your career folder.")
    end

    def accept_all
      drafted = Knowledge::Project.drafted.to_a
      drafted.each { |p| p.update!(status: "accepted", accepted_at: Time.current) }
      Knowledge::Publisher.call
      Onboarding.unskip!("knowledge")
      go_to("knowledge", notice: "Accepted #{drafted.size} #{'project'.pluralize(drafted.size)}.")
    end

    def rewrite
      @project.queue!(note: params[:note].to_s.strip.presence)
      go_to_project(notice: "Rewriting #{@project.name}.")
    end

    # For work that is not on this computer: a lost laptop, a client's GitLab.
    def create
      attrs = params.require(:project).permit(:name, :client, :role, :period, :url, :one_liner, :stack, :highlights)
      return go_to("knowledge", alert: "Give the project a name.") if attrs[:name].blank?

      data = {
        "name" => attrs[:name].strip, "role" => attrs[:role].presence, "client" => attrs[:client].presence,
        "period" => attrs[:period].presence, "url" => attrs[:url].presence, "one_liner" => attrs[:one_liner].presence,
        "stack" => attrs[:stack].to_s.split(",").map(&:strip).reject(&:blank?).presence,
        "highlights" => attrs[:highlights].to_s.lines.map { |l| l.strip.sub(/\A[-*•]\s*/, "") }.reject(&:blank?).presence,
        "tags" => Knowledge::Publisher.normalize_tags(attrs[:stack].to_s.split(",")).presence
      }.compact
      project = Knowledge::Project.create!(scan: Knowledge::Scan.current, name: data["name"], manual: true,
                                           stem: "manual-#{SecureRandom.hex(4)}", client: data["client"], url: data["url"],
                                           status: "accepted", included: true, accepted_at: Time.current,
                                           draft_yaml: data.to_yaml.delete_prefix("---\n"))
      Knowledge::Publisher.call
      Onboarding.unskip!("knowledge")
      go_to("knowledge", notice: "Added #{project.name} to your career folder.")
    end

    private

    # The value the person changed: the field if it differs from what was
    # saved, otherwise the write-up's own line if that differs, otherwise
    # what was saved. Blank clears it.
    def changed(attrs, key, data, current)
      field = attrs.key?(key) ? attrs[key].to_s.strip.presence : :absent
      yaml = data ? data[key.to_s].to_s.strip.presence : :absent
      return field if field != :absent && field != current.presence
      return yaml if yaml != :absent && yaml != current.presence

      current.presence
    end

    def forget(scan)
      scan.projects.where.not(status: "accepted").destroy_all
      scan.projects.update_all(knowledge_scan_id: nil)
      scan.destroy
      Knowledge::Publisher.call
    end

    def set_scan
      @scan = Knowledge::Scan.current
      go_to("knowledge", alert: "Choose a folder first.") if @scan.nil? && action_name != "restart"
    end


    def set_project
      @project = Knowledge::Project.find(params[:id])
    end

    # Back to the same page, which Turbo morphs in place: the list keeps its
    # scroll position, so ticking the twentieth project does not jump to the top.
    def go_to_project(_project = @project, **flash)
      go_to("knowledge", **flash)
    end
  end
end
