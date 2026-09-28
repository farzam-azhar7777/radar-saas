# The check failures that have exactly one right answer, fixed in code.
#
# An em dash becomes a hyphen. A bold glyph in the client's preview becomes the
# plain letter. A proposal a few hundred characters over Upwork's limit loses
# its last related project, which is what the spec says to cut first anyway.
#
# Each of these used to go back to the model: 24 seconds to five minutes for a
# change a string replacement makes in a millisecond, and the model sometimes
# rewrote more than it was asked to.
module ProposalAutofix
  Result = Struct.new(:sections, :fixed, keyword_init: true)

  DASH = /[—–]/
  # 2019–2021 is a range and keeps its shape. Anywhere else a dash is a clause
  # break, which reads the same with a spaced hyphen.
  RANGE_DASH = /(?<=\d)[—–](?=\d)/
  CLAUSE_DASH = /[ \t]*[—–][ \t]*/

  module_function

  def call(sections)
    dashes = 0
    unbolded = 0
    preview_left = ProposalCheck::PREVIEW_CHARS

    fixed_sections = Array(sections).map do |s|
      body = s.body.to_s

      if (n = body.scan(DASH).size).positive?
        dashes += n
        body = plain_dashes(body)
      end

      # The preview is the start of the cover letter, so only letter parts
      # spend it. Answers have their own boxes and their bold is not seen there.
      if s.role.to_s == "letter" && preview_left.positive?
        body, n, used = unbold_prefix(body, preview_left)
        unbolded += n
        preview_left -= used
      end

      ProposalSectioner::Section.new(label: s.label, role: s.role, body: body)
    end

    fixed = []
    fixed << "Replaced #{dashes} em or en #{dashes == 1 ? 'dash' : 'dashes'} with hyphens" if dashes.positive?
    fixed << "Bold removed from the #{ProposalCheck::PREVIEW_CHARS} characters the client previews" if unbolded.positive?
    Result.new(sections: fixed_sections, fixed: fixed)
  end

  def plain_dashes(text) = text.gsub(RANGE_DASH, "-").gsub(CLAUSE_DASH, " - ")

  # Walks the text the way the preview reads it, a run of whitespace counting
  # as one character, and unbolds only what falls inside the window. NFKC maps
  # each mathematical bold glyph to its plain letter and nothing else is touched.
  def unbold_prefix(text, budget)
    seen = 0
    changed = 0
    in_space = true
    out = +""

    text.each_char do |c|
      if seen >= budget
        out << c
        next
      end

      if c.match?(/\s/)
        seen += 1 unless in_space
        in_space = true
      else
        seen += 1
        in_space = false
      end

      if c.match?(ProposalCheck::FANCY)
        out << c.unicode_normalize(:nfkc)
        changed += 1
      else
        out << c
      end
    end

    # Letter parts are joined by a blank line, which the preview reads as one space.
    [ out, changed, [ seen + 1, budget ].min ]
  end

  # Over Upwork's limit, drop related projects from the end until it fits,
  # always keeping one. Returns nil when dropping cannot fix it, because losing
  # projects and still being over is worse than handing the whole job to a repair.
  def trim_projects(sections, limit: ProposalCheck::MAX_CHARS)
    current = Array(sections)
    return nil if characters(current) <= limit

    dropped = []
    while characters(current) > limit
      current, name = drop_last_project(current)
      return nil if current.nil?

      dropped << name
    end

    Result.new(sections: current,
               fixed: [ "Dropped #{dropped.map { |d| %("#{d}") }.join(' and ')} from related projects to fit Upwork's #{limit} characters" ])
  end

  def characters(sections) = ProposalCheck.characters(ProposalAssembler.call(sections))

  # Two layouts reach here: one part per project, or one part holding a heading
  # and a blank-line-separated project each.
  def drop_last_project(sections)
    portfolio = sections.select { |s| s.role.to_s == "portfolio" }

    if portfolio.size >= 2
      last = portfolio.last
      return [ sections.reject { |s| s.equal?(last) }, first_line(last.body).presence || last.label ]
    end

    return nil if portfolio.empty?

    part = portfolio.first
    blocks = part.body.to_s.strip.split(/\n[ \t]*\n+/)
    heading = blocks.first if blocks.size > 1 && heading?(blocks.first)
    projects = blocks - [ heading ].compact
    return nil if projects.size < 2

    kept = [ heading, *projects[0...-1] ].compact.join("\n\n")
    trimmed = ProposalSectioner::Section.new(label: part.label, role: part.role, body: kept)
    [ sections.map { |s| s.equal?(part) ? trimmed : s }, first_line(projects.last) ]
  end

  def heading?(block)
    one_line = !block.strip.include?("\n")
    one_line && (block.match?(ProposalCheck::FANCY) || block.match?(ProposalParts::EXAMPLES) || block.strip.length < 40)
  end

  # Plain, because this name is shown to him in a note, not sent to a client.
  def first_line(text)
    text.to_s.strip.lines.first.to_s.strip.gsub(ProposalCheck::FANCY) { |c| c.unicode_normalize(:nfkc) }
        .sub(/\s+-\s.*\z/, "").truncate(60)
  end
end
