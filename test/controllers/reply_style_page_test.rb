require "test_helper"

class ReplyStylePageTest < ActionDispatch::IntegrationTest
  test "the page opens on the example, saves your own, and restores the example" do
    get edit_reply_style_path
    assert_select "textarea[name='reply_style[rules]']", text: /HOW TO WRITE TO THE CLIENT/
    assert_select "a", text: "Restore the example", count: 0

    patch reply_style_path, params: { reply_style: { rules: "Short. {name}.", turn: "New: {client_message}" } }
    assert_redirected_to edit_reply_style_path
    get edit_reply_style_path
    assert_select "textarea[name='reply_style[turn]']", text: "New: {client_message}"

    delete reply_style_path
    assert_not ReplyStyle.own?
  end

  test "a turn that would hide the client's message is refused, keeping what was typed" do
    patch reply_style_path, params: { reply_style: { rules: "Mine", turn: "Write something." } }
    assert_response :unprocessable_entity
    assert_select "textarea[name='reply_style[rules]']", text: "Mine"
    assert_not ReplyStyle.own?
  end

  test "settings and the conversation both lead here" do
    get settings_path
    assert_select "a[href=?]", edit_reply_style_path
  end
end
