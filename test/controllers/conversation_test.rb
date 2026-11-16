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
    ConversationReply.define_singleton_method(:call) { |*| ConversationReply::Result.new(body: "Yes.", role: "me", session_id: "s-1", meta: { "session_id" => "s-1" }) }
    @posting.update!(reply_queued_at: Time.current)
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
    @posting.update!(reply_queued_at: Time.current)
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

  test "a pasted Upwork conversation becomes separate messages, and the client's last one gets a reply" do
    Profile.current.update!(full_name: "Sohair Ahmad")
    assert_enqueued_with(job: DraftReplyJob) do
      post job_posting_messages_path(@posting), params: { message: { body: file_fixture("upwork_conversation.txt").read, note: "keep it short" } }
    end
    assert_equal %w[client me client], @posting.messages.reload.map(&:role)
    assert_equal "keep it short", @posting.messages.last.note
    assert_equal "Added 3 messages. Writing your reply.", flash[:notice]
  end

  test "pasting the conversation again adds only what is new" do
    Profile.current.update!(full_name: "Sohair Ahmad")
    @posting.messages.create!(role: "client", body: "Thanks Sohair, no")
    @posting.update!(conversation_session_id: "s-1")

    post job_posting_messages_path(@posting), params: { message: { body: "Shai Gecelter\n1:09 AM\nThanks Sohair, no\n\nSohair Ahmad\n1:20 AM\nHere are my answers." } }
    assert_equal [ "Thanks Sohair, no", "Here are my answers." ], @posting.messages.reload.map(&:body)
    assert_match "The last one is yours, so there is nothing to reply to yet", flash[:notice]
    assert_not @posting.replying?

    post job_posting_messages_path(@posting), params: { message: { body: "Sohair Ahmad\n1:20 AM\nHere are my answers." } }
    assert_match "Nothing new", flash[:notice]
  end

  test "while a reply is written the panel shows the same live loader as a proposal" do
    @posting.messages.create!(role: "client", body: "Hi")
    @posting.update!(reply_queued_at: Time.current)
    get job_posting_path(@posting)
    assert_select "#conversation [data-controller=generation][data-generation-pane-value='#conversation']" do
      assert_select "[data-generation-target=bar]"
      assert_select "[data-generation-target=elapsed]"
    end
  end

  test "Ask Radar adds a private question and gets it answered in the same thread" do
    @posting.messages.create!(role: "client", body: "Pick one area.")
    assert_enqueued_with(job: DraftReplyJob) do
      post job_posting_messages_path(@posting), params: { message: { role: "ask", body: "Which area suits me best?" } }
    end
    assert_equal "ask", @posting.messages.last.role

    original = ConversationReply.method(:call)
    ConversationReply.define_singleton_method(:call) { |*| ConversationReply::Result.new(body: "The restaurant one.", role: "radar", session_id: "s-1", meta: { "session_id" => "s-1" }) }
    @posting.update!(reply_queued_at: Time.current)
    DraftReplyJob.perform_now(@posting)
    ConversationReply.define_singleton_method(:call, original)

    get job_posting_path(@posting)
    assert_select "##{ActionView::RecordIdentifier.dom_id(@posting.messages.last)}", text: /Radar.*only you see this.*The restaurant one\./m
    assert_select "#conversation input[type=radio][name='message[role]'][value=ask]"
  end

  test "Stop gives the box back, and whatever that run writes is thrown away" do
    @posting.messages.create!(role: "ask", body: "A follow-up check-in please")
    @posting.update!(reply_queued_at: Time.current)
    job = DraftReplyJob.new(JobPosting.find(@posting.id))

    get job_posting_path(@posting)
    assert_select "#conversation form[action=?] button", stop_job_posting_messages_path(@posting), text: "Stop"

    post stop_job_posting_messages_path(@posting)
    assert_not @posting.reload.replying?

    original = ConversationReply.method(:call)
    ConversationReply.define_singleton_method(:call) { |*| ConversationReply::Result.new(body: "Late", role: "me", session_id: "s", meta: {}) }
    job.perform_now
    ConversationReply.define_singleton_method(:call, original)
    assert_equal "ask", @posting.messages.reload.last.role

    get job_posting_path(@posting)
    assert_select "#conversation .notice", text: /Radar hasn't answered your last message\./
    assert_select "form[action=?] button", redraft_job_posting_messages_path(@posting), text: "Answer now"
  end

  test "an Upwork thread pasted under Ask Radar is still split into messages" do
    Profile.current.update!(full_name: "Sohair Ahmad")
    post job_posting_messages_path(@posting), params: { message: { role: "ask", body: "Here is the latest:\n" + file_fixture("upwork_conversation.txt").read } }
    assert_equal %w[client me client], @posting.messages.reload.map(&:role)
  end
end
