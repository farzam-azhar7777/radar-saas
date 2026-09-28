# Rewrites ONE named part of a proposal and leaves the rest alone.
#
# The whole point is what this prompt does NOT carry. A full generation sends
# the entire spec, the career database instructions, the archetype reasoning
# and the previous draft, and takes minutes. Changing the opening needs the
# job, the part, the note, and enough of the surrounding proposal not to
# contradict it. That is a much smaller ask, and it costs and takes a fraction.
#
# Tool access stays read-only, same as the generator: Radar does not write into
# the career repo except when a job is marked applied.
class SectionRewriter
  # A part is one part. Nothing here needs the 15 minutes a full write can take.
  TIMEOUT = Integer(ENV.fetch("RADAR_SECTION_TIMEOUT", 300))

  # Enough of the post to write against without paying for a 9000-character
  # description that mostly repeats itself.
  DESCRIPTION_CHARS = 1200

  # The parts either side of the one being rewritten, in enough detail not to
  # repeat them. The rest are named only. Sending all eleven parts at 400
  # characters each cost more in context than it ever bought in coherence.
  NEIGHBOUR_CHARS = 320

  # Falls back to the writer's model, so a rewritten part reads like the rest.
  def self.model = ENV["RADAR_SECTION_MODEL"].presence || Radar.writer_model

  class RewriteError < StandardError; end

  Result = Struct.new(:body, :duration_ms, :meta, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(section, feedback:)
    @section = section
    @proposal = section.proposal
    @posting = @proposal.job_posting
    @feedback = feedback.to_s
  end

  def call
    started = Time.current
    text, meta = run(prompt)
    body = clean(text)
    raise RewriteError, "the rewrite came back empty" if body.blank?

    Result.new(body: body, duration_ms: ((Time.current - started) * 1000).to_i, meta: meta)
  end

  private

  def prompt
    parts = []
    parts << "#{Profile.first_name} has a finished Upwork proposal. They want ONE part of it changed. Every other part stays exactly as it is."
    # Deliberately not "read these files first". The finished proposal below
    # already shows the voice and names the projects, which is the whole
    # difference between this and writing one from scratch. Mandatory reads
    # made a one-part rewrite cost more than regenerating the entire proposal.
    parts << "The proposal below already shows their voice and the projects in play, so work from it. " \
             "Only read a file if you genuinely need a fact that is not here: projects/_index.yml for a project " \
             "the proposal does not already name, skills.yml for a version or tool, profile.yml for rate or availability."
    parts << ""
    parts << "---"
    parts << "THE JOB"
    parts << "Title: #{@posting.title}"
    parts << ""
    parts << @posting.description.to_s.truncate(DESCRIPTION_CHARS)

    if (questions = @posting.screening_questions_list).any?
      parts << ""
      parts << "Its screening questions:"
      parts += questions.map.with_index(1) { |q, i| "#{i}. #{q}" }
    end

    parts << ""
    parts << "---"
    parts << "THE PROPOSAL AS IT STANDS. This is context only. Do NOT rewrite any of it except the one part named below."
    parts << ""
    parts << outline
    parts << ""
    parts << "---"
    parts << "THE PART TO REWRITE: #{@section.display_label.inspect}#{" (screening answer #{answer_number})" if @section.answer?}"
    parts << ""
    parts << "Its current text:"
    parts << @section.body.to_s
    parts << ""
    parts << "What #{Profile.first_name} wants changed about it:"
    parts << @feedback
    parts << ""
    parts << "---"
    parts << rules
    parts << ""
    parts << "Output ONLY the new text for this one part, inside a single fenced block. No commentary, no part name, no marker line."
    parts.join("\n")
  end

  # The parts either side in enough detail not to repeat them or contradict
  # them; the rest by name only. Coherence is mostly a local property, and
  # sending eleven parts in full is what made this cost more than it saved.
  def outline
    all = @proposal.sections.to_a
    here = all.index { |s| s.id == @section.id } || 0

    all.map.with_index do |s, i|
      next ">>> #{s.display_label} <<<  THE PART YOU ARE REWRITING. Its current text is below, in full." if i == here

      if (i - here).abs == 1
        "--- #{s.display_label} (the part #{i < here ? 'before' : 'after'} it) ---\n#{s.body.to_s.squish.truncate(NEIGHBOUR_CHARS)}"
      else
        "--- #{s.display_label} --- (#{s.word_count} words, unchanged)"
      end
    end.join("\n\n")
  end

  def rules
    lines = []
    lines << "RULES"
    lines << "- Change only what the note asks for. Everything else about this part stays."
    lines << "- Keep its bold Unicode heading if it has one, on its own first line, unchanged."
    lines << "- It has to still join up with the parts either side of it. No repeating a project or a number another part already used."
    lines << "- Hyphens, never em or en dashes. Contractions. Every claim carries a specific: a project, a number, a version, a tool."
    lines << "- Never invent a project, a metric, a client or a date that is not in the career files."
    # Found by running it: a rewritten answer pasted his Upwork profile URL in,
    # which fails the whole proposal's checks on a rule the part never saw.
    lines << "- Never link their Upwork profile. Upwork attaches it automatically, and linking it fails the proposal's checks."
    lines << "- Never use any of these: #{ProposalCheck::BANNED.join(', ')}."

    if @section.answer?
      lines << "- This is a screening answer. Answer the question in the first sentence. #{ProposalArchetype::ANSWER_WORDS.min} to #{ProposalArchetype::ANSWER_WORDS.max} words, prose, at most two bullets."
      lines << "- Do not start it with a number. The numbering is added afterwards."
    elsif opening?
      lines << "- This is the opening, and it is the only thing the client sees before deciding whether to open the proposal."
      lines << "- Lead with the hardest quantified proof that matches what they asked for, then a phrase that promises what comes next."
      lines << "- Do NOT open with a question, with their name or years, or by restating their brief. No bold glyphs: they cost two characters each in the preview."
    else
      lines << "- Roughly #{[ @section.word_count, 40 ].max} words unless the note asks for longer or shorter. The whole proposal has to stay under #{ProposalCheck::MAX_CHARS} characters."
    end

    if (block = Lesson.prompt_block(saved_search: @posting.saved_search, archetype: @proposal.archetype))
      lines << ""
      lines << block
    end

    lines << ""
    lines << voice_section
    lines.compact.join("\n")
  end

  def opening? = @proposal.sections.reject(&:answer?).first&.id == @section.id

  def answer_number = @proposal.sections.select(&:answer?).index { |s| s.id == @section.id }.to_i + 1

  # Only the Voice part of the spec. Sending all of it would give back the cost
  # this whole feature exists to save.
  def voice_section
    ProposalSpec.section("Voice").presence || ""
  rescue StandardError
    ""
  end

  def clean(text)
    blocks = text.to_s.scan(/```[a-zA-Z]*\n(.*?)```/m).flatten
    body = blocks.last&.strip.presence || text.to_s.strip
    # A marker line coming back would be assembled into the visible proposal.
    body.lines.reject { |l| l.match?(ProposalSectioner::MARKER) }.join.strip
  end

  def run(text)
    result = ClaudeRun.call(text, timeout: TIMEOUT, model: self.class.model, label: "section rewrite")
    [ result.text, result.meta ]
  rescue ClaudeRun::Error => e
    raise RewriteError, e.message
  end
end
