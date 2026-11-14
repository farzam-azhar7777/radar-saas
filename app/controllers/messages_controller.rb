class MessagesController < ApplicationController
  before_action :set_posting

  def create
    return redirect_to(conversation, notice: "Radar is still writing your last reply.") if @posting.replying?

    message = @posting.messages.new(params.expect(message: %i[body note]).merge(role: "client"))
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

  def conversation = job_posting_path(@posting, anchor: "conversation")

  def set_posting
    @posting = JobPosting.find(params[:job_posting_id])
  end
end
