module ReplyStyle
  RULES = "reply_rules".freeze
  TURN = "reply_turn".freeze

  EXAMPLE_RULES = <<~TXT.strip.freeze
    HOW TO REPLY
    - This is an Upwork chat message, not another proposal. Short and direct, usually 40 to 150 words.
    - Answer every question the client asked, in order, with specifics: a project, a number, a tool.
    - End with one clear next step or one useful question.
    - Never promise a rate, a date, availability or a deliverable that the profile, the proposal or {name}'s note does not give. When it is needed and missing, say {name} will confirm it.
    - No greeting fluff, no sign-off block, no signature.
    - Hyphens. Never em dashes or en dashes. Contractions. Plain text, no bold glyphs.
    - Never: {banned}.
  TXT

  EXAMPLE_TURN = <<~TXT.strip.freeze
    THE CLIENT'S NEW MESSAGE
    {client_message}

    {name}'s note for this reply: {note}

    Write {name}'s reply. Output only the message, inside a single fenced block.
  TXT

  PLACEHOLDERS = {
    "{name}" => "your first name",
    "{client_message}" => "what the client wrote (the turn needs it)",
    "{note}" => "your note for this reply; a line with it is left out when there is no note",
    "{banned}" => "the words proposals never use"
  }.freeze

  module_function

  def rules = Setting.get(RULES).presence || EXAMPLE_RULES
  def turn = Setting.get(TURN).presence || EXAMPLE_TURN
  def own? = Setting.where(key: [ RULES, TURN ]).exists?

  def errors(turn:)
    turn.to_s.include?("{client_message}") ? [] : [ "The turn needs {client_message}, or Claude never sees what the client wrote" ]
  end

  def save(rules:, turn:)
    { RULES => [ rules, EXAMPLE_RULES ], TURN => [ turn, EXAMPLE_TURN ] }.each do |key, (value, example)|
      value = value.to_s.gsub("\r\n", "\n").strip
      value.blank? || value == example ? Setting.clear(key) : Setting.set(key, value)
    end
  end

  def restore! = Setting.where(key: [ RULES, TURN ]).delete_all

  def rules_for(name:) = fill(rules, name: name)

  def turn_for(name:, client_message:, note:)
    text = note.present? ? turn : turn.lines.reject { |l| l.include?("{note}") }.join
    fill(text, name: name, client_message: client_message, note: note)
  end

  def fill(text, **values)
    values[:banned] = ProposalCheck::BANNED.join(", ")
    values.reduce(text) { |out, (key, value)| out.gsub("{#{key}}") { value.to_s } }
  end
end
