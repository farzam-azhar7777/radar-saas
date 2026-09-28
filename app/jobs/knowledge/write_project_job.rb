# Writes one chosen project up. Several run at once, one per thread on the
# knowledge queue, so twenty projects take minutes rather than an hour.
class Knowledge::WriteProjectJob < ApplicationJob
  queue_as :knowledge

  discard_on ActiveJob::DeserializationError

  def perform(project)
    return unless project.status == "queued"

    project.update!(status: "writing")
    project.scan&.broadcast

    result = Knowledge::Synthesizer.call(project)
    project.update!(status: "drafted", draft_yaml: result.yaml, open_questions: result.questions,
                    meta: result.meta, drafted_at: Time.current, error: nil, note: nil)
  rescue Knowledge::Synthesizer::Error, StandardError => e
    Rails.logger.error("[Knowledge::WriteProjectJob] #{project.name}: #{e.class}: #{e.message}")
    project.update_columns(status: "failed", error: e.message.to_s.first(600), updated_at: Time.current)
  ensure
    project.scan&.broadcast
  end
end
