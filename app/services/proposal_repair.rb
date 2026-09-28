# Fixing a finished proposal that failed its checks, without writing it again.
#
# The old repair path was a second full generation: the entire spec, the entire
# job, the previous draft, and an instruction to do it all better. It cost as
# much as the first attempt and roughly doubled the wall clock, which is how a
# proposal came to take ten minutes.
#
# Almost every failure is local. The letter is forty words long, a banned word
# appeared, the projects block pushed it over the character limit. The text is
# already written and already good; what it needs is an edit, not a rewrite.
#
# So this sends the parts, the failures, and nothing else, and asks for back
# only the parts that have to change.
class ProposalRepair
  TIMEOUT = Integer(ENV.fetch("RADAR_REPAIR_TIMEOUT", 300))

  class RepairError < StandardError; end

  Result = Struct.new(:sections, :duration_ms, :meta, :changed, keyword_init: true)

  def self.call(...) = new(...).call

  # The generator passes what is left of its deadline, so a repair can never
  # be the reason a proposal takes ten minutes.
  def initialize(posting, sections:, failures:, shape:, timeout: TIMEOUT)
    @posting = posting
    @sections = sections
    @failures = Array(failures)
    @shape = shape
    @timeout = timeout
  end

  def call
    raise RepairError, "nothing to repair" if @sections.empty? || @failures.empty?

    run = ClaudeRun.call(prompt, timeout: @timeout, model: Radar.writer_model, label: "proposal repair")
    fixed = ProposalSectioner.call(ClaudeRun.fenced(run.text), posting: @posting, min_markers: 1)
    raise RepairError, "the repair came back with no parts" if fixed.empty?

    merged = merge(fixed)
    Result.new(sections: merged, duration_ms: run.duration_ms, meta: run.meta,
               changed: fixed.map(&:label))
  end

  private

  # Only the parts that came back are replaced. Everything else survives
  # untouched, which is the difference between an edit and a rewrite.
  def merge(fixed)
    by_label = fixed.index_by { |s| s.label.to_s.downcase.strip }

    @sections.map do |original|
      replacement = by_label[original.label.to_s.downcase.strip]
      next original if replacement.nil?

      ProposalSectioner::Section.new(label: original.label, role: original.role, body: replacement.body)
    end
  end

  def prompt
    lines = []
    lines << "A finished Upwork proposal for #{Profile.first_name} failed its automated checks. Fix only what is broken."
    lines << "The writing is already good. This is an edit, not a rewrite."
    lines << ""
    lines << "---"
    lines << "WHAT FAILED"
    lines += @failures.map { |f| "- #{f}" }
    lines << ""
    lines << "---"
    lines << "THE PROPOSAL, PART BY PART"
    @sections.each do |s|
      lines << ""
      lines << "=== #{s.label} | #{s.role} ===   (#{words(s)} words)"
      lines << s.body.to_s
    end
    lines << ""
    lines << "---"
    lines << rules
    lines << ""
    lines << "Output ONLY the parts you changed, inside a single fenced block, each under its own marker line " \
             "using its label EXACTLY as written above:"
    lines << ""
    lines << "=== Label | role ==="
    lines << ""
    lines << "Do not output the parts you did not change. Do not add new parts. Do not rename anything."
    lines.join("\n")
  end

  def rules
    <<~TXT.strip
      RULES
      - Change the fewest parts that fix the failures. A part that is not at fault stays as it is.
      - Keep each part about the length it is. Do not pad a part to fix something else.
      - The whole proposal must fit #{ProposalCheck::MAX_CHARS} characters, everything counted together.
        When it is over, cut the related projects block first and the answers second. Never buy space by
        shortening the letter: the letter is what wins the job.
      - Keep every bold Unicode heading exactly where it is.
      - Hyphens, never em or en dashes. Never any of these: #{ProposalCheck::BANNED.join(', ')}.
      - Never invent a project, number, client or date that is not already in the proposal.
      - Do not number the screening answers. The numbering is added afterwards.
    TXT
  end

  def words(section) = section.body.to_s.split(/\s+/).reject(&:blank?).size
end
