# One definition of how a proposal body divides up.
#
# Proposal and ProposalCheck each grew their own copy, and they drifted: the
# anchoring bug that made a letter ending in a portfolio block resolve to the
# answers was fixed in one and not the other, so the check measured a 439-word
# proposal as a 94-word letter and demanded it be padded.
class ProposalParts
  SEPARATOR = /^\s*-{5,}\s*$/

  # Anchored. A letter that ENDS with a portfolio block still contains the
  # phrase; matching anywhere threw the letter away.
  EXAMPLES = /\A(?:Examples of My Work|Related Projects|RELATED PROJECTS|\u{1D5D8}\u{1D605}|\u{1D5E5}\u{1D5E4})/i
  ANSWER_BLOCK = /\A\s*\d+[.)]\s/

  def initialize(body, has_questions: false)
    @body = body.to_s
    @has_questions = has_questions
  end

  def sections
    @sections ||= @body.split(SEPARATOR).map(&:strip).reject(&:blank?)
  end

  # Screening answers sit above the letter and only exist when the post had
  # formal questions to answer.
  def answer_block
    return nil unless @has_questions
    return nil if sections.size < 2

    sections.first.match?(ANSWER_BLOCK) ? sections.first : nil
  end

  def answers_list
    block = answer_block
    return [] if block.blank?

    block.split(/^\s*(?=\d+[.)]\s)/)
         .map { |a| a.sub(/\A\s*\d+[.)]\s*/, "").strip }
         .reject(&:blank?)
  end

  # Everything that is neither the answers nor the portfolio block.
  def letter
    return @body.strip if sections.empty?

    skip = answer_block
    remaining = sections.reject { |part| part.match?(EXAMPLES) || (skip && part == skip) }
    remaining.first.presence || sections.first
  end

  def preview(chars = 250) = letter.gsub(/\s+/, " ").strip.first(chars)
end
