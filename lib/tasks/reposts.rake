namespace :radar do
  desc "Flag jobs already seen that repeat an earlier job, and pass over unwritten ones posted too often"
  task flag_reposts: :environment do
    flagged = 0
    JobPosting.order(:created_at, :id).each do |posting|
      EarlierCopies.flag!(posting)
      next unless posting.repost_of_id_changed? || posting.repost_count_changed?

      posting.update_columns(repost_of_id: posting.repost_of_id, repost_count: posting.repost_count)
      flagged += 1
    end
    before = JobPosting.where(status: "matched").count
    JobPosting.where(repost_count: EarlierCopies::SKIP_FROM..).find_each { |p| EarlierCopies.pass_over_unwritten(p) }
    puts "Flagged #{flagged} reposts. Passed over #{before - JobPosting.where(status: 'matched').count} unwritten inbox jobs."
  end
end
