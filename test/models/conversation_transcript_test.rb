require "test_helper"

class ConversationTranscriptTest < ActiveSupport::TestCase
  def parse(text) = ConversationTranscript.parse(text, me: [ "Sohair Ahmad", "Sohair" ])

  test "an Upwork conversation is split by speaker, with the times, dates and extra blank lines left out" do
    messages = parse(file_fixture("upwork_conversation.txt").read)

    assert_equal %w[client me client], messages.map(&:role)
    assert messages[0].body.start_with?("Hi Sohair, thanks for the proposal.")
    assert messages[0].body.end_with?("1. Pick ONE of the 3 areas.\nShai")
    assert_no_match(/\n{3}/, messages[0].body)
    assert_equal "Hey Shai.\n\nI will get back to you on these.\n\nThanks for responding.", messages[1].body
    assert_equal "Thanks Sohair, no", messages[2].body
  end

  test "a second message from the same person, shown with only a time, is its own message" do
    messages = parse("Shai Gecelter\n10:30 PM\nFirst\n\n10:32 PM\nSecond\n")
    assert_equal [ %w[client First], %w[client Second] ], messages.map { |m| [ m.role, m.body ] }
  end

  test "a plain message with no names or times is not a transcript" do
    assert_nil parse("Can you start Tuesday?\nAlso, what is your rate?")
  end
end
