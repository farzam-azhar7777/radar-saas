class PassedOverAdvice
  MOVES_NEEDED = 3
  WINDOW = 60.days
  DISMISSED = "passed_over_advice_dismissed".freeze

  Suggestion = Data.define(:search, :to, :moves, :would_clear) do
    def key = "line:#{search.id}:#{search.threshold}:#{to}"
  end

  def self.suggestions
    dismissed = JSON.parse(Setting.get(DISMISSED, "[]"))
    moved = JobPosting.where(moved_back_at: WINDOW.ago..).to_a.select { |p| p.passed_over_for.to_h["kind"] == "score" }
    moved.group_by { |p| p.passed_over_for["search_id"] }.filter_map do |search_id, moves|
      search = SavedSearch.find_by(id: search_id)
      scores = moves.map { |p| p.passed_over_for["score"].to_i }.select { |s| s < search&.threshold.to_i }
      next if search.nil? || scores.size < MOVES_NEEDED

      suggestion = Suggestion.new(search:, to: scores.min, moves: scores.size, would_clear: clearing(search, scores.min).count)
      suggestion unless dismissed.include?(suggestion.key)
    end
  end

  def self.clearing(search, line)
    JobPosting.from_upwork.where(status: "ignored", saved_search: search, score: line...search.threshold, created_at: 7.days.ago..)
              .reject { |p| PassReason.for(p).kind != "score" }
  end

  def self.apply!(search, to)
    moving = clearing(search, to)
    search.update!(threshold: to)
    JobPosting.where(id: moving.map(&:id)).update_all(status: "matched")
    moving.size
  end

  def self.dismiss!(key)
    Setting.set(DISMISSED, (JSON.parse(Setting.get(DISMISSED, "[]")) | [ key ]).to_json)
  end
end
