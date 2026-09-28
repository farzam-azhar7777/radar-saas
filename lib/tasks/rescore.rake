# Scores are stored, not computed on read, so a change to the weights or to a
# search's bar leaves every existing posting judged by the old rules. This
# re-applies the current rules to what is already in the database.
#
# It never enqueues a generation. Rescoring history must not spend money on jobs
# that are days old, however well they score now.
namespace :radar do
  # Recency measures how fresh a job was WHEN IT WAS JUDGED. Recomputing it now
  # would mark every posting down for the crime of having been found yesterday,
  # which is not a change in the rules, only a change in the clock. So the
  # recency it earned at discovery is carried across, rescaled if the weight
  # moved. Everything else is judged fresh.
  def freeze_recency(posting, outcome)
    was = Array(posting.score_reasons).find { |r| r["key"] == "recency" }
    now = outcome.reasons.find { |r| r["key"] == "recency" }
    return outcome unless was && now && was["max"].to_i.positive?

    kept = (was["points"].to_f / was["max"].to_f * now["max"].to_i).round
    # Read the fresh value before overwriting it. `now` is the same object the
    # reasons array holds, so mutating first makes the correction cancel itself.
    fresh = now["points"].to_i
    now["points"] = kept
    now["note"] = was["note"]

    ScoreJobPosting::Result.new(score: outcome.score - fresh + kept, reasons: outcome.reasons)
  end

  desc "Re-apply the current scoring rules to existing postings (no generation)"
  task rescore: :environment do
    dry = ENV["APPLY"].blank?
    moved = { into_inbox: [], out_of_inbox: [] }
    unchanged = 0

    # Anything Farzam has acted on is left exactly as it is.
    scope = JobPosting.where(status: %w[matched ignored]).includes(:saved_search)

    active = SavedSearch.active.ordered.to_a
    rehomed = 0

    scope.find_each do |posting|
      next unless posting.saved_search

      # Re-apply the current rules means the homing rule too, not just the
      # weights. A posting homed under the old rule keeps scoring under it.
      search = BestSearchFor.call(posting, fallback: posting.saved_search, searches: active)
      rehomed += 1 if search.id != posting.saved_search_id

      outcome = freeze_recency(posting, ScoreJobPosting.call(posting, saved_search: search, searches: active))
      status = outcome.score >= search.threshold.to_i ? "matched" : "ignored"

      if status == posting.status && outcome.score == posting.score.to_i && search.id == posting.saved_search_id
        unchanged += 1
        next
      end

      if status != posting.status
        key = status == "matched" ? :into_inbox : :out_of_inbox
        moved[key] << [ posting, posting.score.to_i, outcome.score ]
      end

      unless dry
        posting.update_columns(score: outcome.score,
                               score_reasons: outcome.reasons.as_json,
                               saved_search_id: search.id,
                               status: status)
      end
    end

    puts dry ? "DRY RUN. Re-run with APPLY=1 to write." : "APPLIED."
    puts "  unchanged: #{unchanged}"
    puts "  re-homed to a different search: #{rehomed}"
    puts "  into the inbox: #{moved[:into_inbox].size}"
    moved[:into_inbox].sort_by { |_, _, n| -n }.first(25).each do |p, o, n|
      puts "    #{o}->#{n}  #{p.saved_search.name.ljust(17)} #{p.title.to_s[0, 58]}"
    end
    puts "  out of the inbox: #{moved[:out_of_inbox].size}"
    moved[:out_of_inbox].sort_by { |_, _, n| n }.first(25).each do |p, o, n|
      puts "    #{o}->#{n}  #{p.saved_search.name.ljust(17)} #{p.title.to_s[0, 58]}"
    end
  end
end
