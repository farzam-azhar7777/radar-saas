require "test_helper"

class ConversationReplyTest < ActiveSupport::TestCase
  setup do
    @posting = JobPosting.create!(upwork_id: "conv-1", title: "Voice agent", description: "Wire Twilio to an LLM agent.",
                                  status: "applied", score: 80)
    @posting.proposals.create!(version: 1, body: "I built Sera, a Twilio voice agent on Rails.")
  end

  def claude(fail_resume: false, text: "```\nHappy to — Tuesday works.\n```")
    calls = []
    original = ClaudeRun.method(:call)
    ClaudeRun.define_singleton_method(:call) do |prompt, **opts|
      calls << { prompt: prompt, opts: opts }
      raise ClaudeRun::Error, "No conversation found" if fail_resume && opts[:resume]

      ClaudeRun::Result.new(text: text, duration_ms: 5, meta: { "session_id" => "s-#{calls.size}" })
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
      assert_equal [ "Happy to, Tuesday works.", "s-1", "me" ], [ result.body, result.session_id, result.role ]
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
    @posting.messages.create!(role: "me", body: "Yes, Tuesday.", claude_meta: { "session_id" => "gone" })
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

  test "asking Radar privately gets a private answer, or a draft for the client when that is what was asked" do
    @posting.update!(conversation_session_id: "s-old")
    @posting.messages.create!(role: "client", body: "Pick one area and tell me your first week.")
    @posting.messages.create!(role: "me", body: "I will get back to you.", claude_meta: { "session_id" => "s-old" })
    @posting.messages.create!(role: "ask", body: "Which area suits me best?")

    claude(text: "The restaurant platform. You built Sera.") do |calls|
      result = ConversationReply.call(@posting)
      assert_equal [ "radar", "The restaurant platform. You built Sera." ], [ result.role, result.body ]
      assert_match(/ASKS YOU PRIVATELY\nWhich area suits me best\?/, calls.sole[:prompt])
      assert_match "the client never sees this", calls.sole[:prompt]
    end

    claude(text: "```\nHi Shai, here is my first week.\n```") do
      assert_equal [ "me", "Hi Shai, here is my first week." ], ConversationReply.call(@posting).to_h.values_at(:role, :body)
    end
  end

  test "messages you sent yourself since the last draft reach a resumed session in order" do
    @posting.update!(conversation_session_id: "s-old")
    @posting.messages.create!(role: "client", body: "Hi", claude_meta: {})
    @posting.messages.create!(role: "me", body: "Drafted", claude_meta: { "session_id" => "s-old" })
    @posting.messages.create!(role: "me", body: "I also sent this myself.")
    @posting.messages.create!(role: "client", body: "Great, what next?")

    claude do |calls|
      ConversationReply.call(@posting)
      assert_match(/SENT THE CLIENT\nI also sent this myself\..*Great, what next\?/m, calls.sole[:prompt])
    end
  end

  test "nothing is asked of Claude when the last message is your own" do
    @posting.messages.create!(role: "client", body: "Hi")
    @posting.messages.create!(role: "me", body: "Hello")
    claude do |calls|
      assert_raises(ConversationReply::Error) { ConversationReply.call(@posting) }
      assert_empty calls
    end
  end

  test "when there is nothing to send the client, Radar says so to you privately instead of drafting" do
    @posting.messages.create!(role: "client", body: "Should a short check-in be enough?")
    claude(text: "That reads like your own question. A two-line check-in is enough.") do |calls|
      assert_equal "radar", ConversationReply.call(@posting).role
      assert_match "answer #{Profile.first_name} in plain text with no fenced block", calls.sole[:prompt]
    end
  end

  test "the example rules ask for Sohair's own tone and short check-ins" do
    @posting.messages.create!(role: "client", body: "Any update?")
    claude do |calls|
      ConversationReply.call(@posting)
      assert_match "Copy the length and tone of the messages", calls.sole[:prompt]
      assert_match "A follow-up or check-in is 1 to 3 sentences", calls.sole[:prompt]
    end
  end
end
