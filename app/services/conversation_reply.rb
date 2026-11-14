class ConversationReply
  TIMEOUT = 300

  class Error < StandardError; end

  Result = Struct.new(:body, :session_id, :meta, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(posting)
    @posting = posting
    @messages = posting.messages.to_a
  end

  def call
    raise Error, "there is no client message to reply to" if waiting.empty?

    run = resumed || ClaudeRun.call(opening + turn, timeout: TIMEOUT, model: Radar.writer_model, label: "conversation reply")
    body = ProposalAutofix.plain_dashes(ClaudeRun.fenced(run.text))
    raise Error, "Claude came back with an empty reply" if body.blank?

    Result.new(body: body, session_id: run.meta["session_id"], meta: run.meta)
  end

  private

  def first_name = Profile.first_name

  def last_reply_index = @messages.rindex { |m| !m.client? }

  def history = last_reply_index ? @messages[..last_reply_index] : []

  def waiting = @messages.drop(history.size)

  def resumed
    return unless @posting.conversation_session_id

    ClaudeRun.call(sent_note + turn, timeout: TIMEOUT, model: Radar.writer_model, label: "conversation reply",
                   resume: @posting.conversation_session_id)
  rescue ClaudeRun::Error => e
    Rails.logger.warn("[ConversationReply] #{@posting.id}: could not resume, starting from the saved thread: #{e.message}")
    nil
  end

  def opening
    proposal = @posting.latest_proposal
    lines = []
    lines << "You are #{first_name}, a freelancer. #{first_name} sent the proposal below for this Upwork job, and the client " \
             "has written back. From here on you write #{first_name}'s messages in this conversation, one at a time."
    lines << "This folder is #{first_name}'s career folder. Read CLAUDE.md, profile.yml and writing-voice.md before your " \
             "first reply, and read the project files when the client asks about specific experience. State only facts you " \
             "find there, in the proposal or in the conversation."
    lines << ""
    lines << "---"
    lines << "THE JOB"
    lines << "Title: #{@posting.title}"
    lines << "Budget: #{@posting.budget_label}"
    lines << ""
    lines << @posting.description.to_s.truncate(4000)
    lines << ""
    lines << "---"
    lines << "THE PROPOSAL #{first_name.upcase} SENT"
    lines << (proposal&.body.presence || "(not recorded)")
    if history.any?
      lines << ""
      lines << "---"
      lines << "THE CONVERSATION SO FAR"
      history.each { |m| lines << "#{speaker(m)}:\n#{m.body}\n" }
    end
    lines << ""
    lines.join("\n")
  end

  def sent_note
    last = history.last
    return "" unless last && !last.client?

    "#{first_name}'s last message, exactly as it was sent (it may differ from your draft):\n#{last.body}\n\n"
  end

  def turn
    notes = waiting.filter_map { |m| m.note.presence }
    [ "---", ReplyStyle.rules_for(name: first_name), "---",
      ReplyStyle.turn_for(name: first_name, client_message: waiting.map(&:body).join("\n\n"), note: notes.join(" ")) ].join("\n")
  end

  def speaker(message) = message.client? ? "Client" : first_name
end
