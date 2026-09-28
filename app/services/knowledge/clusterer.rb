module Knowledge
  # Repositories become products.
  #
  # A client hires for "the Fast 800 app", not for fast800-api-with-web and
  # fast800-app-frontend separately. Repos are grouped by the stem of their
  # name once the words that only describe a slice of a product are removed.
  #
  # Deliberately not by remote organisation: an agency keeps a dozen unrelated
  # products under one org. The person can merge and split in the UI anyway;
  # this only has to be a good first guess.
  module Clusterer
    SLICE_WORDS = %w[
      api web app apps frontend front backend back end fe be client server admin dashboard
      portal site website mobile ios android native service services svc worker workers
      core main v1 v2 v3 v4 new old legacy test tests testing staging prod demo with and the
    ].to_set.freeze

    module_function

    def stem(name)
      words = name.to_s
                  .gsub(/([a-z])([A-Z])/, '\1 \2')
                  .downcase
                  .split(/[^a-z0-9]+/)
                  .reject { |w| w.blank? || SLICE_WORDS.include?(w) || w.match?(/\A(rails|react|next|node|ruby|python)\d*\z/) || w.match?(/\A\d+\z/) }
      joined = words.join
      joined.presence || name.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end

    # Groups the scan's repos into projects, keeping every decision the person
    # already made about a stem: its name, its status, whether it is excluded.
    def call(scan)
      scan.repos.where("own_commits > 0").group_by { |r| stem(r.name) }.each do |key, repos|
        project = scan.projects.find_or_initialize_by(stem: key)
        project.name = display_name(repos) if project.new_record?
        project.save!
        # Repos the person moved by hand stay where they put them.
        repos.each { |r| r.update!(knowledge_project_id: project.id) if r.knowledge_project_id.nil? }
      end

      scan.projects.where(manual: false).find_each do |project|
        project.destroy if project.repos.none? && %w[candidate].include?(project.status)
      end

      Ranker.call(scan)
    end

    # The most-worked repo's name, made readable: "weguide_medical" reads as
    # "Weguide Medical". The person renames it to what a client would say.
    def display_name(repos)
      raw = repos.max_by(&:own_commits).name
      raw.tr("_-", "  ").split.map { |w| w.match?(/\A[a-z]/) ? w.capitalize : w }.join(" ")
    end
  end
end
