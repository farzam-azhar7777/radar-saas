# Questions a client buried in the job description, as opposed to Upwork's
# screeningQuestions field.
#
# The distinction decides where the answers go, and it is not cosmetic. Formal
# screening questions get their own boxes on Upwork's form and render above the
# cover letter, so answering them above the letter is correct. Questions in the
# description have no boxes: everything goes into the one cover-letter textarea.
# Answering those at the top pushes the hook out of the 250 characters the
# client sees in their list, and it is the client's only reason to open you.
class DescriptionQuestions
  # Cues come in two strengths, and the difference matters. "To apply" is
  # unambiguously the application ask. "Please include" is more often a
  # deliverable: one post used it for "please include post-delivery support"
  # and for sanitized API fixtures, neither of which is a question. Taking the
  # first cue found made scope bullets look like an application checklist, so a
  # strong cue anywhere in the post wins over every weak one.
  STRONG_CUE = /^\s*[*#>\s]*(?:to apply\b|how to apply\b|when applying\b|to be considered\b|before applying\b|answer the following\b|please answer\b|in your\s+(?:proposal|application|cover letter|response|reply)\b|your (?:proposal|application) should\b)/i

  WEAK_CUE = /^\s*[*#>\s]*(?:please\s+(?:submit|provide|share|send|reply|tell|include)|tell\s+(?:me|us)\b|include the following\b|i(?:'|\u2019)?d like to know\b|let me know\b)/i

  # A numbered or bulleted line: "1. Your CV", "- Years of experience".
  ITEM = /^\s*(?:\d+[.)]|[-*•])\s+(.+?)\s*$/

  MAX = 10
  MIN_LENGTH = 8

  def self.call(...) = new(...).call

  def initialize(posting)
    @posting = posting
  end

  def call
    return [] if @posting.screening_questions_list.any?

    (after_cue(STRONG_CUE).presence || after_cue(WEAK_CUE).presence || bare_questions).first(MAX)
  end

  private

  def lines = @posting.description.to_s.split(/[\r\n]+/)

  # The list following a cue, stopping where the list stops. Every cue of the
  # given strength is tried, and the longest list wins: a post often mentions
  # "please provide" in passing before the real checklist.
  def after_cue(cue)
    lines.each_index.filter_map { |i| collect_from(i) if lines[i].match?(cue) }.max_by(&:size).to_a
  end

  def collect_from(index)
    found = []

    lines[(index + 1)..].to_a.each do |line|
      next if found.empty? && line.strip.blank?

      if (m = line.match(ITEM))
        found << clean(m[1])
      elsif found.any?
        break
      elsif line.strip.present?
        break
      end
    end

    found.reject(&:blank?)
  end

  # No cue, but the post asks outright. Only direct questions, so a rhetorical
  # "Struggling with slow queries?" opener is not mistaken for a requirement.
  def bare_questions
    lines.filter_map { |l|
      s = clean(l.sub(ITEM, '\1'))
      s if s.end_with?("?") && s.length >= MIN_LENGTH && s.split.size >= 3
    }
  end

  def clean(text) = text.to_s.gsub(/\s+/, " ").gsub(/^[*_#]+|[*_]+$/, "").strip
end
