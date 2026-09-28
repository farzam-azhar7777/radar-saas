class Proposal < ApplicationRecord
  belongs_to :job_posting

  # The editable view of the same text. body stays authoritative: everything
  # downstream reads it, and assembling from these is what keeps the two equal.
  has_many :sections, -> { ordered }, class_name: "ProposalSection",
           dependent: :destroy, inverse_of: :proposal

  validates :version, presence: true

  # When this proposal actually landed. generated_at is set by the job, but a
  # row written by anything else still has to answer the question, or a rewrite
  # that finished would keep reading as still running.
  def finished_at = generated_at || created_at

  SEPARATOR = ProposalParts::SEPARATOR
  EXAMPLES = ProposalParts::EXAMPLES
  ANSWER_BLOCK = ProposalParts::ANSWER_BLOCK

  # Upwork gives formal screening questions their own input boxes. The cover
  # letter box takes only the letter, so handing over one blob with the answers
  # on top made the client's list preview read "1. Yes. Sera is a Rails 7.2...".
  def parts
    @parts ||= ProposalParts.new(body, has_questions: job_posting&.screening_questions_list&.any?)
  end

  delegate :answer_block, :answers_list, :letter, :preview, to: :parts

  def word_count
    body.to_s.split(/\s+/).reject(&:blank?).size
  end

  def letter_word_count = letter.split(/\s+/).reject(&:blank?).size

  # CLAUDE.md sets the cover-letter target at 120 to 220 words.
  def within_target_length?
    word_count.between?(120, 220)
  end

  # --- parts ---------------------------------------------------------------

  # Every proposal written before this feature existed still has to be editable
  # part by part, so the parts are derived on first use rather than backfilled
  # in a migration that could not have seen the bodies it was splitting.
  def ensure_sections!
    return sections if sections.any? || body.blank?

    # Locked and re-checked: the pane derives these on render, and a double
    # click or a Turbo broadcast landing at the same moment as a page load
    # would otherwise insert two sets of parts for one proposal.
    with_lock do
      return sections if sections.reset.any?

      build_sections_from(ProposalSectioner.call(body, posting: job_posting))
    end
    sections.reset
  end

  def build_sections_from(parsed)
    rows = Array(parsed).each_with_index.map do |s, i|
      { proposal_id: id, position: i, label: s.label.to_s.first(70).presence || "Part #{i + 1}",
        role: s.role, body: s.body.to_s, created_at: Time.current, updated_at: Time.current }
    end
    return [] if rows.empty?

    ProposalSection.insert_all!(rows)
  end

  # What the assembler would produce from the current parts. Equal to body
  # unless something wrote one without the other.
  def assembled = ProposalAssembler.call(sections.to_a)

  # Everything that goes in Upwork's cover letter box: the letter AND the
  # related projects block underneath it.
  #
  # ProposalParts#letter deliberately stops at the signature, so the word
  # budget measures the argument and not the portfolio. The copy button read
  # that same method, so the projects block he ends every proposal with was
  # neither shown on screen nor copied to the clipboard.
  def cover_letter_text
    parts = sections.reject(&:answer?)
    return ProposalAssembler.call(parts) if parts.any?

    ProposalAssembler.call(ProposalSectioner.call(body, posting: job_posting).reject { |s| s.role == "answer" })
  end

  def rewriting_section = sections.detect(&:rewriting?)
  def rewriting_part? = rewriting_section.present?

  # Set when this version came from rewriting one part rather than the whole
  # proposal, so the version list can say which part changed.
  def rewritten_section_label
    (claude_meta.is_a?(Hash) ? claude_meta["rewritten_section"] : nil).presence
  end

  def part_rewrite? = rewritten_section_label.present?

  def to_fix = Array(verdict["failures"])
  def notes = Array(verdict["notes"])
  def auto_fixed = Array(verdict["fixed"])

  # Proposals written before 2026-09-25 stored a single failure list in which
  # 480 words against 460 counted the same as being over Upwork's limit.
  # Read them again under the current split rather than show a word count as
  # something to fix before sending.
  def verdict
    return {} unless checks.is_a?(Hash)
    return checks if checks.empty? || checks.key?("notes") || body.blank?

    @legacy_verdict = nil if @legacy_verdict&.first != body
    (@legacy_verdict ||= [ body, ProposalCheck.call(body, archetype: ProposalArchetype.call(job_posting),
                                                          posting: job_posting).deep_stringify_keys ]).last
  end

  # One line for a notification: what, if anything, he has to do before sending.
  def readiness
    return "#{to_fix.size} #{to_fix.size == 1 ? 'thing' : 'things'} to fix before sending" if to_fix.any?

    notes.any? ? "Ready to send, #{notes.size} #{notes.size == 1 ? 'note' : 'notes'}" : "Ready to send"
  end
end
