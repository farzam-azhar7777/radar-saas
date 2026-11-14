require "test_helper"

class ReplyStyleTest < ActiveSupport::TestCase
  test "starts with the example, filled in" do
    assert_not ReplyStyle.own?
    assert_match "Never promise a rate", ReplyStyle.rules_for(name: "Farzam")
    assert_match(/Never: .+\./, ReplyStyle.rules_for(name: "Farzam"))
    assert_no_match(/\{\w+\}/, ReplyStyle.rules_for(name: "Farzam"))
  end

  test "the turn carries the client's message, and drops the note line when there is no note" do
    with_note = ReplyStyle.turn_for(name: "Farzam", client_message: "Cost? \\1", note: "quote $45/hr")
    assert_match "Cost? \\1", with_note
    assert_match "Farzam's note for this reply: quote $45/hr", with_note

    assert_no_match "note for this reply", ReplyStyle.turn_for(name: "Farzam", client_message: "Cost?", note: "")
  end

  test "saving your own replaces the example, and saving the example or nothing keeps following it" do
    ReplyStyle.save(rules: "Be brief, {name}.", turn: "Client said: {client_message}")
    assert ReplyStyle.own?
    assert_equal "Be brief, Farzam.", ReplyStyle.rules_for(name: "Farzam")

    ReplyStyle.save(rules: ReplyStyle::EXAMPLE_RULES, turn: " ")
    assert_not ReplyStyle.own?
  end

  test "a turn without the client's message is refused" do
    assert_not_empty ReplyStyle.errors(turn: "Write a reply.")
    assert_empty ReplyStyle.errors(turn: "{client_message}")
  end
end
