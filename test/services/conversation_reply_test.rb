require "test_helper"

class ConversationReplyTest < ActiveSupport::TestCase
  setup do
    @posting = JobPosting.create!(upwork_id: "conv-1", title: "Voice agent", description: "Wire Twilio to an LLM agent.",
                                  status: "applied", score: 80)
    @posting.proposals.create!(version: 1, body: "I built Sera, a Twilio voice agent on Rails.")
  end

  def claude(fail_resume: false)
    calls = []
    original = ClaudeRun.method(:call)
    ClaudeRun.define_singleton_method(:call) do |prompt, **opts|
      calls << { prompt: prompt, opts: opts }
      raise ClaudeRun::Error, "No conversation found" if fail_resume && opts[:resume]

      ClaudeRun::Result.new(text: "```\nHappy to — Tuesday works.\n```", duration_ms: 5, meta: { "session_id" => "s-#{calls.size}" })
    end
    yield calls
  ensure
    ClaudeRun.define_singleton_method(:call, original)
  end

  test "the first reply opens a session with the job, the proposal sent, the client's message and the note" do
    @posting.messages.create!(role: "client", body: "Can you start Tuesday?", note: "say yes")
    claude do |calls|
      result = ConversationReply.call(@posting)
      prompt = calls.sole[:prompt]

      assert_nil calls.sole[:opts][:resume]
      assert_match "Wire Twilio to an LLM agent.", prompt
      assert_match "I built Sera, a Twilio voice agent on Rails.", prompt
      assert_match "Can you start Tuesday?", prompt
      assert_match "note for this reply: say yes", prompt
      assert_equal [ "Happy to - Tuesday works.", "s-1" ], [ result.body, result.session_id ]
    end
  end

  test "a later reply resumes the session, sending only what it has not seen, including the reply as edited" do
    @posting.update!(conversation_session_id: "s-old")
    @posting.messages.create!(role: "client", body: "Can you start Tuesday?")
    @posting.messages.create!(role: "me", body: "Yes, Tuesday. Edited by hand.", claude_meta: { "session_id" => "s-old" })
    @posting.messages.create!(role: "client", body: "What would it cost?")

    claude do |calls|
      ConversationReply.call(@posting)
      assert_equal "s-old", calls.sole[:opts][:resume]
      assert_match "Yes, Tuesday. Edited by hand.", calls.sole[:prompt]
      assert_match "What would it cost?", calls.sole[:prompt]
      assert_no_match "I built Sera", calls.sole[:prompt]
    end
  end

  test "a lost session is rebuilt from the saved conversation" do
    @posting.update!(conversation_session_id: "gone")
    @posting.messages.create!(role: "client", body: "Can you start Tuesday?")
    @posting.messages.create!(role: "me", body: "Yes, Tuesday.")
    @posting.messages.create!(role: "client", body: "What would it cost?")

    claude(fail_resume: true) do |calls|
      ConversationReply.call(@posting)
      fresh = calls.last
      assert_nil fresh[:opts][:resume]
      assert_match(/THE CONVERSATION SO FAR.*Can you start Tuesday\?.*Yes, Tuesday\./m, fresh[:prompt])
      assert_match(/THE CLIENT'S NEW MESSAGE\nWhat would it cost\?/, fresh[:prompt])
    end
  end

  test "with nothing from the client to answer, nothing is asked of Claude" do
    claude do |calls|
      assert_raises(ConversationReply::Error) { ConversationReply.call(@posting) }
      assert_empty calls
    end
  end

  test "your own rules and turn are what Claude is told, on a resumed session too" do
    ReplyStyle.save(rules: "Always mention {name}'s timezone.", turn: "Client wrote >> {client_message} <<")
    @posting.update!(conversation_session_id: "s-old")
    @posting.messages.create!(role: "client", body: "Can you start Tuesday?")
    claude do |calls|
      ConversationReply.call(@posting)
      assert_match(/Always mention \w+'s timezone\./, calls.sole[:prompt])
      assert_match "Client wrote >> Can you start Tuesday? <<", calls.sole[:prompt]
      assert_no_match "HOW TO REPLY", calls.sole[:prompt]
    end
  end
end
