# Picks the shape a proposal should take, from what Radar already knows about
# the client and the competition. Nobody writing by hand has these numbers at
# the moment of writing, which is the whole point.
class ProposalArchetype
  # Cut on 2026-11-20. The budgets raised on 2026-09-23 (320 to 460 words) put
  # the average proposal at 3,954 characters, and long, dense letters were the
  # plainest sign that nobody wrote them by hand. Bids that get read are short.
  #
  # The budget governs the letter. The related-projects block is counted
  # separately, so it never eats into the argument.
  SHAPES = {
    "A" => { name: "Few bids or new client", words: 140..200 },
    "B" => { name: "Established client",     words: 120..180 },
    "C" => { name: "High competition",       words: 90..140 },
    "E" => { name: "Vague post",             words: 90..150 }
  }.freeze

  # Screening questions used to shrink the letter to 90-140 words while the
  # answers themselves had no budget at all. The result was a 464-word runbook
  # of answers above a 131-word letter: the answers did all the talking and the
  # thing that actually sells, the letter, was a stub. The letter now keeps its
  # archetype budget whatever else is true, and the answers are what get capped.
  ANSWER_WORDS = 30..60

  # Upwork puts several questions in one field often enough that counting
  # fields under-counts the work. "What is your approach to Rails upgrades.
  # What is your approach to Postgres upgrades. Can you showcase past work."
  # is one field and three answers.
  MAX_SUBQUESTIONS = 6

  # Questions asked in the description have no boxes on Upwork's form, so their
  # answers live inside the letter and the letter has to grow to hold them.
  # Tighter than a screening answer because they sit in the flow of a pitch.
  INLINE_ANSWER_WORDS = 15..35

  # Upwork hard-rejects a proposal over 5000 characters, and here the answers
  # are part of the same text box, so the letter cannot grow without limit.
  MAX_LETTER_WORDS = 650

  MAX_CHARACTERS = 2_400
  SMALL_JOB_CHARACTERS = 1_600
  CHARACTERS_PER_EXTRA_ANSWER = 300
  SMALL_JOB_WORDS = 60..110
  SMALL_JOB_PRICE = 500

  HIGH_COMPETITION = 80
  FEW_BIDS = 15
  ESTABLISHED_SPEND = 10_000
  ESTABLISHED_HIRES = 5
  VAGUE_DESCRIPTION = 400

  attr_reader :posting

  def self.call(...) = new(...).call

  def initialize(posting)
    @posting = posting
  end

  def call
    { key: key, name: SHAPES.fetch(key)[:name], words: words, max_characters: max_characters,
      has_questions: questions?, question_count: question_count,
      answer_words: answer_words, inline_questions: posting.inline_questions,
      signals: signals }
  end

  def key
    return "C" if bids > HIGH_COMPETITION
    return "E" if vague?
    return "B" if established?
    "A"
  end

  def words
    base = small_job? ? SMALL_JOB_WORDS : SHAPES.fetch(key)[:words]
    n = posting.inline_questions.size
    return base if n.zero?

    (base.min + INLINE_ANSWER_WORDS.min * n)..[ base.max + INLINE_ANSWER_WORDS.max * n, MAX_LETTER_WORDS ].min
  end

  def max_characters
    extra = [ question_count + posting.inline_questions.size - 3, 0 ].max
    [ (small_job? ? SMALL_JOB_CHARACTERS : MAX_CHARACTERS) + CHARACTERS_PER_EXTRA_ANSWER * extra, ProposalCheck::MAX_CHARS ].min
  end

  # How many distinct things actually have to be answered.
  def question_count
    return 0 unless questions?

    posting.screening_questions_list.sum { |q| subquestions(q) }.clamp(1, MAX_SUBQUESTIONS)
  end

  # The whole answer block, not one answer. This is the number the client's
  # attention budget actually cares about.
  def answer_words
    return nil unless questions?

    (ANSWER_WORDS.min * question_count)..(ANSWER_WORDS.max * question_count)
  end

  # The label stored on the proposal, so the UI and the lessons can group by it.
  def label = questions? ? "#{key}+D" : key

  private

  # A question field split across lines is usually several questions. Fall back
  # to sentence-ish counting when it is one run-on line.
  def subquestions(field)
    lines = field.to_s.split(/[\r\n]+/).map(&:strip).reject(&:blank?)
    return lines.size if lines.size > 1

    [ field.to_s.scan(/[.?!]\s+(?=[A-Z])|[.?!]\z/).size, 1 ].max
  end

  def bids = posting.total_applicants.to_i
  def spend = posting.client_total_spent.to_f
  def questions? = posting.screening_questions_list.any?
  def vague? = posting.description.to_s.length < VAGUE_DESCRIPTION
  def small_job? = posting.fixed_amount.present? && posting.fixed_amount.to_f <= SMALL_JOB_PRICE
  def established? = spend > ESTABLISHED_SPEND && posting.client_total_hires.to_i >= ESTABLISHED_HIRES

  def signals
    [
      *(bid_signal if bids_known?),
      *(client_signals if client_known?),
      questions? ? "#{posting.screening_questions_list.size} screening questions" : nil,
      posting.budget_label,
      posting.engagement.presence,
      posting.duration_label.presence
    ].compact
  end

  def bids_known? = !posting.pasted? || !posting.total_applicants.nil?

  def client_known? = !posting.pasted? || posting.client_known?

  def bid_signal = "#{bids} #{'proposal'.pluralize(bids)} already submitted"

  def client_signals
    [
      spend.positive? ? "client has spent $#{spend.round}" : "client has no spend history",
      posting.client_payment_verified? ? "payment verified" : "payment NOT verified",
      posting.client_total_hires.to_i.positive? ? "#{posting.client_total_hires} previous hires" : "no previous hires",
      posting.client_rating.to_f.positive? ? "#{posting.client_rating.to_f.round(1)} star rating" : nil
    ]
  end
end
