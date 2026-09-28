# One git repository in the scanned folder, with what the history says.
class Knowledge::Repo < ApplicationRecord
  belongs_to :scan, class_name: "Knowledge::Scan", foreign_key: :knowledge_scan_id
  belongs_to :project, class_name: "Knowledge::Project", foreign_key: :knowledge_project_id, optional: true

  def share
    return 0 if total_commits.to_i.zero?

    ((own_commits.to_f / total_commits) * 100).round
  end

  def stack_names = Knowledge::StackDetector.flatten(stack)

  def span_label = Knowledge::Project.span(first_own_at, last_own_at)

  # Where the repo is relative to the folder that was scanned, which is how
  # the person recognises it.
  def relative_path
    Pathname.new(path).relative_path_from(scan.root).to_s
  rescue ArgumentError
    path
  end
end
