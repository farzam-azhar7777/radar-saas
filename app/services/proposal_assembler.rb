# Puts named parts back together into the one blob Upwork actually receives.
#
# Everything downstream - ProposalCheck, ProposalParts, the client preview, the
# copy buttons - reads the assembled body and knows nothing about sections. So
# the output here has to be byte-for-byte the shape those were written against:
# answers, a five-hyphen rule, the letter, a long rule, the projects block.
module ProposalAssembler
  # ProposalCheck fails a proposal with screening answers and no separator,
  # because without it the letter budget silently measures the answers too.
  ANSWER_RULE = "-----".freeze
  PORTFOLIO_RULE = ("-" * 41).freeze

  module_function

  def call(sections)
    parts = Array(sections).reject { |s| body_of(s).blank? }
    answers   = parts.select { |s| role_of(s) == "answer" }
    portfolio = parts.select { |s| role_of(s) == "portfolio" }
    letter    = parts - answers - portfolio

    out = []
    # Numbering is owned here, so an answer rewritten without its "3." cannot
    # renumber the block behind his back.
    out << answers.map.with_index(1) { |s, i| "#{i}. #{body_of(s)}" }.join("\n\n") if answers.any?
    out << ANSWER_RULE if answers.any? && letter.any?
    out << letter.map { |s| body_of(s) }.join("\n\n") if letter.any?

    # A rule before each trailing block, not one before all of them. Two
    # portfolio blocks joined by a blank line read as one long block.
    portfolio.each do |s|
      out << PORTFOLIO_RULE
      out << body_of(s)
    end

    out.reject(&:blank?).join("\n\n")
  end

  # Works with both ProposalSectioner::Section and the persisted record.
  def body_of(section) = section.body.to_s.strip
  def role_of(section) = section.role.to_s
end
