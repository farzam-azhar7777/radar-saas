class DraftReplyJob < ApplicationJob
  queue_as :generation

  discard_on ActiveJob::DeserializationError

  after_discard do |job, _error|
    job.arguments.first.update_columns(reply_queued_at: nil)
  rescue StandardError
    nil
  end

  def perform(posting)
    reply = ConversationReply.call(posting)
    posting.messages.create!(role: "me", body: reply.body, claude_meta: reply.meta)
    posting.update_columns(conversation_session_id: reply.session_id || posting.conversation_session_id, reply_queued_at: nil, reply_error: nil)
  rescue ConversationReply::Error, ClaudeRun::Error => e
    Rails.logger.error("[DraftReplyJob] #{posting.id}: #{e.message}")
    posting.update_columns(reply_queued_at: nil, reply_error: e.message.to_s.first(400))
  ensure
    Turbo::StreamsChannel.broadcast_replace_to("job_posting_#{posting.id}", target: "conversation",
                                               partial: "messages/conversation", locals: { posting: posting.reload })
  end
end
