# Turns a proposal into named parts, so one part can be rewritten without
# paying to regenerate the other nine.
#
# The part NAMES are not fixed. A Rails migration post and a vague one-liner
# want different shapes, and forcing both into the same five headings would
# undo the thing that makes the proposals good. So the writer names its own
# parts and only tags each with a ROLE, which is the minimum the assembler
# needs in order to put the text back together in the right places.
#
# Two ways in, and both must work:
#   parse   - a freshly written proposal carrying "=== Label | role ===" markers
#   derive  - any older proposal, or one where the markers were ignored
#
# derive is not a nicety. 145 proposals existed before this feature, and a
# writer that silently drops the markers must not lose the ability to edit.
class ProposalSectioner
  ROLES = %w[answer letter portfolio].freeze

  # "=== Opening | letter ===", tolerant about spacing, the role, and how many
  # equals signs the model felt like using.
  MARKER = /^[ \t]*={2,}[ \t]*(.+?)[ \t]*(?:\|[ \t]*([A-Za-z_]+)[ \t]*)?={2,}[ \t]*$/

  # Mathematical alphanumerics. A line made mostly of these is a heading.
  FANCY = /[\u{1D400}-\u{1D7FF}]/
  BOLD_ITALIC = /[\u{1D468}-\u{1D4CF}]/

  Section = Struct.new(:label, :role, :body, keyword_init: true)

  def self.call(...) = new(...).call

  # Two markers before we believe them, because a stray "=== something ===" in
  # an ordinary proposal must not be mistaken for structure. A parallel writer
  # is different: it was handed the labels it must emit, so one marker from it
  # is the whole of its output and refusing it silently relabelled every part
  # "Opening".
  def initialize(body, posting: nil, has_questions: nil, min_markers: 2)
    @body = body.to_s
    @posting = posting
    @min_markers = min_markers
    @has_questions =
      if has_questions.nil?
        posting&.screening_questions_list&.any? || false
      else
        has_questions
      end
  end

  def call
    marked = parse
    marked.any? ? marked : derive
  end

  # True when the writer actually obeyed the output contract. Worth knowing:
  # if this goes false across the board the prompt has drifted.
  def marked? = parse.any?

  private

  def parse
    return @parse if defined?(@parse)

    lines = @body.lines
    hits = lines.each_with_index.filter_map { |line, i| [ i, line.match(MARKER) ] if line.match?(MARKER) }
    return @parse = [] if hits.size < @min_markers

    @parse = hits.each_with_index.filter_map do |(index, match), n|
      stop = hits[n + 1]&.first || lines.size
      text = lines[(index + 1)...stop].join.strip
      next if text.blank?

      role = role_for(match[2], match[1])
      # Only an answer loses its leading number: the assembler renumbers those.
      # Stripping it from a letter part would eat a legitimate numbered list.
      Section.new(label: clean_label(match[1]), role: role,
                  body: role == "answer" ? strip_number(text) : text)
    end
  end

  # An unknown or missing role still has to land somewhere sensible.
  def role_for(raw, label)
    role = raw.to_s.downcase.strip
    return role if ROLES.include?(role)
    return "answer" if label.to_s.match?(/\A(?:q(?:uestion)?\s*\d|answer\s*\d)/i)
    return "portfolio" if label.to_s.match?(/related project|examples of my work|portfolio/i)

    "letter"
  end

  # --- deriving from a plain body ------------------------------------------

  def derive
    chunks = @body.split(ProposalParts::SEPARATOR).map(&:strip).reject(&:blank?)
    return [] if chunks.empty?

    answers_first = @has_questions && chunks.first.match?(ProposalParts::ANSWER_BLOCK)
    sections = []

    sections.concat(answer_sections(chunks.first)) if answers_first

    # Anything after the letter is a trailing block, whatever it calls itself.
    # ProposalParts reads the letter as the first chunk that is neither the
    # answers nor a portfolio heading and ignores the rest, so treating a
    # trailing block headed "Reviews on Auto Pilot" as more letter would grow
    # the measured letter by 500 characters the budget never counted.
    letter_seen = false

    # Skipped by index, not by object identity. Comparing freshly split strings
    # with equal? is exactly the bug that once made the answer block never skip.
    chunks.each_with_index do |chunk, i|
      next if answers_first && i.zero?

      if letter_seen || chunk.match?(ProposalParts::EXAMPLES)
        sections << Section.new(label: first_line_label(chunk, "Related projects"), role: "portfolio", body: chunk)
      else
        letter_seen = true
        sections.concat(letter_sections(chunk))
      end
    end

    sections
  end

  # A new answer starts only where the number CONTINUES the sequence, and never
  # past the number of questions actually asked. Splitting on every "1)" turned
  # a four-answer block containing one nested list into ten answers, and the
  # renumbering then rewrote the client's text.
  def answer_sections(chunk)
    questions = @posting&.screening_questions_list || []
    limit = questions.size
    lines = chunk.lines
    starts = []

    lines.each_with_index do |line, i|
      number = line[/\A[ \t]*(\d+)[.)]\s/, 1]
      next if number.nil?
      next unless number.to_i == starts.size + 1
      next if limit.positive? && starts.size >= limit

      starts << i
    end

    return [ Section.new(label: answer_label(questions.first, 0), role: "answer", body: strip_number(chunk)) ] if starts.empty?

    starts.each_with_index.map do |start, i|
      # Sliced, never split and rejoined: the text between two boundaries comes
      # through exactly as it was written, blank lines and indents included.
      from = i.zero? ? 0 : start
      stop = starts[i + 1] || lines.size
      Section.new(label: answer_label(questions[i], i), role: "answer",
                  body: strip_number(lines[from...stop].join.strip))
    end
  end

  def answer_label(question, index)
    return "Answer #{index + 1}" if question.blank?

    "#{index + 1}. #{question.to_s.squish.truncate(64)}"
  end

  # Split a letter on its own headings. The first paragraph is always the
  # opening, because that is the part he rewrites most and the only part the
  # client is guaranteed to see.
  def letter_sections(chunk)
    # rstrip, not strip: a paragraph that opens on an indented sub-list ("   a.
    # Milestone event forgery...") carries that indent as meaning, and stripping
    # it silently reflows the letter.
    paragraphs = chunk.split(/\n{2,}/).map(&:rstrip).reject(&:blank?)
    return [ Section.new(label: "Letter", role: "letter", body: chunk) ] if paragraphs.empty?

    sections = []
    current = { label: "Opening", body: [ paragraphs.first ] }

    paragraphs.drop(1).each do |para|
      head = para.lines.first.to_s.strip

      if heading?(head)
        sections << finish(current)
        current = { label: heading_label(head), body: [ para ] }
      elsif current[:label] == "Opening" && current[:body].size == 1
        sections << finish(current)
        current = { label: "Body", body: [ para ] }
      else
        current[:body] << para
      end
    end

    sections << finish(current)
    sections
  end

  def finish(part) = Section.new(label: part[:label], role: "letter", body: part[:body].join("\n\n"))

  def heading?(line)
    return false if line.blank? || line.length > 70
    return false if line.end_with?(".", ":", "?", ",")

    fancy = line.each_char.count { |c| c.match?(FANCY) }
    fancy.positive? && fancy >= line.delete(" ").length * 0.6
  end

  def heading_label(line)
    return "Signature" if line.match?(BOLD_ITALIC)

    clean_label(line)
  end

  def first_line_label(chunk, fallback)
    line = chunk.lines.first.to_s.strip
    line.present? ? clean_label(line) : fallback
  end

  # NFKC folds the mathematical bold alphabet back to plain letters, so a
  # heading of "𝗠𝘆 𝗥𝗲𝗹𝗲𝘃𝗮𝗻𝘁 𝗦𝗸𝗶𝗹𝗹𝘀" labels the card "My Relevant Skills"
  # without carrying glyphs that cost two characters each.
  def clean_label(text)
    text.to_s.unicode_normalize(:nfkc).squish.truncate(70).presence || "Part"
  end

  # The assembler owns the numbering, so an answer rewritten without its "3."
  # cannot silently renumber the block.
  def strip_number(text) = text.sub(/\A\s*\d+[.)]\s*/, "").strip
end
