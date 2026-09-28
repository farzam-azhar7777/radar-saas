# Job posts are written by humans, so "Full-Stack Developer", "full stack
# developer" and "Full Stack  Developer" are the same job. Plain string
# containment treats them as three different things and silently drops two.
module TextMatch
  module_function

  def normalize(text)
    text.to_s.downcase.tr("-_/,", "    ").gsub(/[^a-z0-9+#.\s]/, " ").squeeze(" ").strip
  end

  def haystack_for(posting)
    normalize([ posting.title, posting.description, Array(posting.skills).join(" ") ].compact.join(" "))
  end

  # Whole-word only. Without this "ror" matches "error" and "next" matches
  # "nextdoor", which put an embedded-hardware job in a Rails inbox.
  def includes?(haystack, term)
    t = normalize(term)
    return false if t.blank?

    haystack.match?(/(?<![a-z0-9])#{Regexp.escape(t)}(?![a-z0-9])/)
  end

  # A human writing a job title drops a word into the middle of the phrase:
  # "Senior Full Stack HEALTHCARE Developer" is a full stack developer post, but
  # contiguous matching sees nothing. This is true when every word of the term
  # appears in order, gaps allowed, so the split phrase still registers.
  #
  # Order matters. Without it "developer stack full" would match, and so would
  # any title long enough to contain the words by accident.
  # The gap is capped. Without a limit this matched "ai engineer" inside
  # "AI-Native Software & Infrastructure Engineer" and "python api" inside
  # "Python/C++ Engineer | Flask, Microservice, API", which are not those jobs.
  # One or two words dropped into a phrase is a human writing a title; four is
  # two unrelated words that happen to appear in order.
  MAX_GAP_WORDS = 2

  def spans?(haystack, term)
    words = normalize(term).split(" ")
    return false if words.empty?
    return includes?(haystack, term) if words.one?

    start = nil
    cursor = 0
    matched = words.all? do |word|
      match = haystack.match(/(?<![a-z0-9])#{Regexp.escape(word)}(?![a-z0-9])/, cursor)
      next false unless match

      start ||= match.begin(0)
      cursor = match.end(0)
      true
    end
    return false unless matched

    span_words = haystack[start...cursor].split(" ").size
    span_words - words.size <= MAX_GAP_WORDS
  end

  def title_of(posting) = normalize(posting.title)
end
