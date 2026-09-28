# Reads every repository's history for the identities the person claimed,
# then groups them into projects and ranks them. No model, no network.
class Knowledge::InventoryJob < ApplicationJob
  queue_as :knowledge

  def perform(scan)
    repos = scan.repos.order(:path).to_a
    scan.update!(status: "inventorying", error: nil)
    scan.progress!(0, repos.size, "Reading your history in #{repos.size} repositories")

    repos.each_with_index do |repo, i|
      Knowledge::Inventory.call(repo, scan)
      scan.progress!(i + 1, repos.size, "Just read: #{repo.name}") if ((i + 1) % 3).zero? || i + 1 == repos.size
    end

    Knowledge::Clusterer.call(scan)
    scan.update!(status: "curating", inventoried_at: Time.current, progress_label: nil)
    scan.broadcast
  rescue StandardError => e
    Rails.logger.error("[Knowledge::InventoryJob] #{e.class}: #{e.message}")
    scan.update!(status: "failed", error: "#{e.class}: #{e.message}".first(500))
    scan.broadcast
  end
end
