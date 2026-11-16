class DraftReplyJob < ApplicationJob
  queue_as :generation

  discard_on ActiveJob::DeserializationError

  after_discard do |job, _error|
    job.arguments.first.update_columns(reply_queued_at: nil)
  rescue StandardError
    nil
  end

  def perform(posting)
    started = posting.reply_queued_at or return
    reply = ConversationReply.call(posting)
    return unless still_wanted?(posting, started)

    posting.messages.create!(role: reply.role, body: reply.body, claude_meta: reply.meta)
    posting.update_columns(conversation_session_id: reply.session_id || posting.conversation_session_id, reply_queued_at: nil, reply_error: nil)
  rescue ConversationReply::Error, ClaudeRun::Error => e
    Rails.logger.error("[DraftReplyJob] #{posting.id}: #{e.message}")
    posting.update_columns(reply_queued_at: nil, reply_error: "Radar could not answer: #{e.message.to_s.first(400)}") if still_wanted?(posting, started)
  ensure
    Turbo::StreamsChannel.broadcast_replace_to("job_posting_#{posting.id}", target: "conversation",
                                               partial: "messages/conversation", locals: { posting: posting.reload })
  end

  private

  def still_wanted?(posting, started) = posting.reload.reply_queued_at.to_i == started.to_i
end
