# Pushes a posting's current state to whichever screens are open. Called both
# when a generation is queued and when it lands, so the inbox row and the
# proposal pane say the same thing as the database at every moment rather than
# only at the end.
#
# Turbo streams are the primary transport. They are also the one part of this
# that fails silently when ActionCable cannot connect, which is why the pane
# carries its own fallback poll.
module BroadcastPosting
  module_function

  def call(posting)
    posting = posting.reload

    Turbo::StreamsChannel.broadcast_replace_to(
      "inbox",
      target: ActionView::RecordIdentifier.dom_id(posting),
      partial: "job_postings/row",
      locals: { posting: posting }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "job_posting_#{posting.id}",
      target: "proposal-pane",
      partial: "job_postings/proposal_pane",
      locals: { posting: posting }
    )
    true
  rescue StandardError => e
    Rails.logger.warn("[BroadcastPosting] #{posting.try(:id)}: #{e.message}")
    false
  end
end
