module ReplyStyle
  RULES = "reply_rules".freeze
  TURN = "reply_turn".freeze

  EXAMPLE_RULES = <<~TXT.strip.freeze
    HOW TO WRITE TO THE CLIENT
    - Write the way {name} types a quick Upwork message: plain, direct, a little informal. Not like an assistant, not like a cover letter.
    - Copy the length and tone of the messages {name} wrote themself in this conversation. With none to go on, keep it short and plain.
    - Most replies are 2 to 5 sentences. A follow-up or check-in is 1 to 3 sentences that only nudge: no new pitch, and no new questions unless {name} asks for them.
    - Answer what the client asked. Add a detail (a project, a number, a tool) only when it answers something.
    - No flattery, and no repeating the client's words back. No clever lines, wordplay or "not X, it's Y". No closing sentence that sums up or explains the message.
    - One next step at most, and only when there is a real one.
    - Never promise a rate, a date, availability or a deliverable that the profile, the proposal or {name}'s note does not give. When it is needed and missing, say {name} will confirm it.
    - No dashes between clauses: use a full stop or a comma. No bullet lists unless the client asked several questions. No bold, no sign-off, no signature.
    - Never: {banned}.

    WHEN {name} ASKS YOU SOMETHING PRIVATELY
    - Answer in a few plain sentences. Advice, not an essay.
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
