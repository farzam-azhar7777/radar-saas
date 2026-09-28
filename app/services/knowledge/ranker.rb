module Knowledge
  # Which projects are most worth pitching, from the history alone.
  #
  #   own commits  45  log-scaled: 1,500 commits is more than 150, not ten times more
  #   share        20  a product they mostly wrote is a stronger claim than one they touched
  #   span         15  months of sustained work beat a burst
  #   recency      20  recent work is what a client asks about
  #
  # The top of the list is pre-ticked. Nothing here is final; it only decides
  # the order the person sees and what is ticked before they look.
  module Ranker
    PRESELECT = 20
    MIN_COMMITS = 10

    module_function

    def call(scan)
      scan.projects.includes(:repos).find_each { |p| rollup(p) }

      untouched = scan.projects.where(status: "candidate").ranked.to_a
      # Only a scan that has never been curated gets defaults; after that the
      # person's own ticks stand.
      if scan.projects.where(included: true).none?
        picks = untouched.select { |p| p.own_commits >= MIN_COMMITS }.first(PRESELECT)
        # A folder of small repos still gets a starting point rather than a
        # wall of empty boxes.
        picks = untouched.first(5) if picks.empty?
        picks.each { |p| p.update_columns(included: true) }
      end
      scan.projects.ranked.each_with_index { |p, i| p.update_columns(position: i + 1) }
    end

    def rollup(project)
      repos = project.repos.to_a
      return if repos.empty?

      own = repos.sum(&:own_commits)
      total = repos.sum(&:total_commits)
      first = repos.filter_map(&:first_own_at).min
      last = repos.filter_map(&:last_own_at).max
      months = repos.sum(&:active_months)

      project.update_columns(own_commits: own, total_commits: total, first_at: first, last_at: last,
                             rank_score: score(own: own, total: total, months: months, last: last).round(2))
    end

    def score(own:, total:, months:, last:)
      return 0 if own.zero?

      volume = [ Math.log10(own + 1) / Math.log10(2000), 1 ].min * 45
      share = total.positive? ? (own.to_f / total) * 20 : 0
      span = [ months / 24.0, 1 ].min * 15
      age_years = last ? (Time.current - last) / 1.year : 10
      recency = [ 1 - age_years / 6.0, 0 ].max * 20
      volume + share + span + recency
    end
  end
end
