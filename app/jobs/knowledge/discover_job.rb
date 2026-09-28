# Finds every repository in the folder and who committed to them, then waits
# for the person to say which authors are them.
class Knowledge::DiscoverJob < ApplicationJob
  queue_as :knowledge

  def perform(scan)
    paths = Knowledge::Discover.with_root(scan.root_path)
    if paths.empty?
      return scan.update!(status: "failed", error: "No git repositories were found in #{scan.root_path}. " \
                                                   "Point Radar at the folder that holds your project folders.")
    end

    scan.progress!(0, paths.size, "Reading who committed to #{paths.size} repositories")
    candidates = Knowledge::Identities.call(paths) { |done, total| scan.progress!(done, total) if (done % 5).zero? || done == total }

    profile = Profile.current
    chosen = candidates.select { |c| Knowledge::Identities.likely_mine?(c, profile) }

    paths.each { |path| scan.repos.find_or_create_by!(path: path) { |r| r.name = File.basename(path) } }
    scan.update!(status: "identities", candidates: candidates,
                 identities: scan.identities.presence || chosen.map { |c| c["email"] },
                 progress_label: nil, error: nil)
    scan.broadcast
  rescue StandardError => e
    Rails.logger.error("[Knowledge::DiscoverJob] #{e.class}: #{e.message}")
    scan.update!(status: "failed", error: "#{e.class}: #{e.message}".first(500))
    scan.broadcast
  end
end
