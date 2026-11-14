class MessagesController < ApplicationController
  before_action :set_posting

  def create
    return redirect_to(conversation, notice: "Radar is still writing your last reply.") if @posting.replying?

    fields = params.expect(message: %i[body note])
    transcript = ConversationTranscript.parse(fields[:body], me: [ Profile.current.full_name, Profile.first_name ])
    return import(transcript, note: fields[:note]) if transcript

    message = @posting.messages.new(fields.merge(role: "client"))
    return redirect_to(conversation, alert: "Paste the client's message first.") unless message.save

    @posting.draft_reply!
    redirect_to conversation, notice: "Writing your reply."
  end

  def update
    @posting.messages.where(role: "me").find(params[:id]).update!(params.expect(message: %i[body]))
    redirect_to conversation, notice: "Saved. The next reply builds on this version."
  end

  def destroy
    @posting.messages.find(params[:id]).destroy!
    @posting.update_columns(conversation_session_id: nil)
    redirect_to conversation, notice: "Removed. The next reply starts from the conversation as it is now."
  end

  def redraft
    @posting.draft_reply! if @posting.messages.last&.client? && !@posting.replying?
    redirect_to conversation
  end

  private

  def import(transcript, note:)
    known = @posting.messages.map { |m| m.body.squish.downcase }
    fresh = transcript.reject { |m| known.include?(m.body.squish.downcase) }
    return redirect_to(conversation, notice: "Nothing new in that paste. Every message is already here.") if fresh.empty?

    added = fresh.map { |m| @posting.messages.create!(role: m.role, body: m.body) }
    added.select(&:client?).last&.update!(note: note.presence)
    @posting.update_columns(conversation_session_id: nil) if added.any? { |m| !m.client? }

    count = "Added #{added.size == 1 ? 'one message' : "#{added.size} messages"}."
    return redirect_to(conversation, notice: "#{count} The last one is yours, so there is nothing to reply to yet.") unless added.last.client?

    @posting.draft_reply!
    redirect_to conversation, notice: "#{count} Writing your reply."
  end

  def conversation = job_posting_path(@posting, anchor: "conversation")

  def set_posting
    @posting = JobPosting.find(params[:job_posting_id])
  end
end
