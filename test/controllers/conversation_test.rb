require "test_helper"

class ConversationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @posting = JobPosting.create!(upwork_id: "conv-2", title: "Voice agent", description: "Wire Twilio to an LLM agent.",
                                  status: "applied", score: 80)
    @posting.proposals.create!(version: 1, body: "I built Sera.")
  end

  test "a job with a proposal offers the conversation, and pasting a message drafts a reply" do
    get job_posting_path(@posting)
    assert_select "#conversation textarea[name='message[body]']"

    assert_enqueued_with(job: DraftReplyJob) do
      post job_posting_messages_path(@posting), params: { message: { body: "Can you start Tuesday?", note: "say yes" } }
    end
    assert_redirected_to job_posting_path(@posting, anchor: "conversation")
    assert_equal [ "client", "Can you start Tuesday?", "say yes" ], @posting.messages.sole.slice(:role, :body, :note).values
    assert @posting.reload.replying?
  end

  test "the drafted reply lands in the thread, keeps the session, and can be edited and copied" do
    @posting.messages.create!(role: "client", body: "Can you start Tuesday?")
    original = ConversationReply.method(:call)
    ConversationReply.define_singleton_method(:call) { |*| ConversationReply::Result.new(body: "Yes.", session_id: "s-1", meta: { "session_id" => "s-1" }) }
    DraftReplyJob.perform_now(@posting)
    ConversationReply.define_singleton_method(:call, original)

    reply = @posting.messages.last
    assert_equal [ "me", "Yes.", "s-1" ], [ reply.role, reply.body, @posting.reload.conversation_session_id ]
    assert_not @posting.replying?

    get job_posting_path(@posting)
    assert_select "##{ActionView::RecordIdentifier.dom_id(reply)} textarea", "Yes."
    assert_select "##{ActionView::RecordIdentifier.dom_id(reply)} button", text: /Copy/

    patch job_posting_message_path(@posting, reply), params: { message: { body: "Yes, Tuesday 10am." } }
    assert_equal "Yes, Tuesday 10am.", reply.reload.body
  end

  test "a failed reply says why and offers to try again" do
    @posting.messages.create!(role: "client", body: "Can you start Tuesday?")
    original = ConversationReply.method(:call)
    ConversationReply.define_singleton_method(:call) { |*| raise ClaudeRun::Error, "claude exited 1" }
    DraftReplyJob.perform_now(@posting)
    ConversationReply.define_singleton_method(:call, original)

    get job_posting_path(@posting)
    assert_match "claude exited 1", response.body
    assert_enqueued_with(job: DraftReplyJob) { post redraft_job_posting_messages_path(@posting) }
  end

  test "removing a message forgets the session, so the next reply is rebuilt from what is left" do
    @posting.update!(conversation_session_id: "s-1")
    wrong = @posting.messages.create!(role: "client", body: "Pasted the wrong thing")
    delete job_posting_message_path(@posting, wrong)
    assert_empty @posting.messages.reload
    assert_nil @posting.reload.conversation_session_id
  end

  test "an empty paste is refused, and a second paste waits for the reply being written" do
    assert_no_enqueued_jobs(only: DraftReplyJob) { post job_posting_messages_path(@posting), params: { message: { body: " " } } }
    assert_equal "Paste the client's message first.", flash[:alert]

    @posting.update!(reply_queued_at: Time.current)
    assert_no_difference("Message.count") { post job_posting_messages_path(@posting), params: { message: { body: "Hello?" } } }
  end

  test "a job with no proposal yet has no conversation" do
    @posting.proposals.delete_all
    get job_posting_path(@posting)
    assert_select "#conversation", 0
  end
end
