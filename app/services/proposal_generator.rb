# Writes a proposal by running Claude Code headless inside the pitchsmith repo,
# so it inherits CLAUDE.md, writing-voice.md, every project file and the real
# rate and availability. Nothing about Farzam's voice lives in this class.
#
# What does live here is strategy: which shape to write in, what Radar knows
# about the client and the competition, and what past feedback has taught.
#
# Every model call goes through ClaudeRun, which is where the read-only tool
# restriction lives that keeps Radar from writing into pitchsmith.
class ProposalGenerator
  class GenerationError < StandardError; end

  Result = Struct.new(:body, :duration_ms, :meta, :archetype, :checks, :attempts, :sections, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(job_posting, feedback: nil, previous: nil, template_name: nil)
    @posting = job_posting
    @feedback = feedback
    @previous = previous
    @template = template_name.presence || job_posting.saved_search&.template_name
    @archetype = ProposalArchetype.new(job_posting)
  end

  # A repair with less time than this left rarely finishes, so it is not started.
  MIN_REPAIR_SECONDS = 60

  # Draft, then fix what has one right answer in code, then send back only a
  # real problem, once, inside the deadline. Whatever is still wrong after
  # that ships beside the draft for Farzam to judge. He rewrites a part in
  # twenty seconds; waiting five minutes for a repair was the worse trade.
  def call
    @started = Time.current
    shape = @archetype.call

    sections, body, meta = draft(shape)
    sections, body, meta = redraft_empty(shape, meta) if body.blank?

    fixed = []
    sections, body = tidy(sections, body, fixed)
    checks = check(body, shape)
    attempts = 1

    if over_limit?(checks) && (trim = ProposalAutofix.trim_projects(sections))
      fixed.concat(trim.fixed)
      sections = trim.sections
      body = ProposalAssembler.call(sections)
      checks = check(body, shape)
    end

    unless checks[:passed]
      attempts = 2
      sections, body, meta = repair(sections, body, checks[:failures], shape, meta, fixed)
      checks = check(body, shape)
    end

    Result.new(body: body, duration_ms: elapsed_ms,
               meta: meta, archetype: @archetype.label, checks: checks.merge(fixed: fixed),
               attempts: attempts, sections: sections)
  end

  private

  # Plan once, then write the parts at the same time. Nearly all of a
  # generation's wall clock is token generation, and tokens come out in series,
  # so the only real lever on speed is to stop generating them one after another.
  #
  # Falls back to writing the whole thing in one pass if either phase fails.
  # A slow proposal is a nuisance; no proposal is a lost job.
  def draft(shape)
    return serial_draft(shape) unless Radar.parallel_generation?

    plan = ProposalPlan.call(@posting, shape: shape, feedback: @feedback, previous: @previous)
    written = ParallelProposalWriter.call(@posting, plan: plan.data, shape: shape)

    sections = written.sections
    raise ParallelProposalWriter::WriteError, "no usable parts" if sections.empty?

    Rails.logger.info("[ProposalGenerator] parallel: plan #{plan.duration_ms / 1000}s, " \
                      "write #{written.duration_ms / 1000}s, #{sections.size} parts")

    [ sections, ProposalAssembler.call(sections), merge_meta(plan.meta, written.meta).merge("mode" => "parallel") ]
  rescue ProposalPlan::PlanError, ParallelProposalWriter::WriteError, ClaudeRun::Error => e
    Rails.logger.warn("[ProposalGenerator] parallel draft failed (#{e.message}), writing it in one pass instead")
    serial_draft(shape)
  end

  # Edits only the parts at fault, with only the time left. A repair that fails
  # or runs out of time leaves the draft exactly as it was. There is no longer
  # a full rewrite behind it: that fallback is what took proposals to ten
  # minutes, and it rewrote parts that were fine.
  def repair(sections, body, failures, shape, meta, fixed)
    left = Radar.generation_deadline - elapsed_ms / 1000
    if sections.blank? || left < MIN_REPAIR_SECONDS
      Rails.logger.info("[ProposalGenerator] not repairing (#{left}s left), shipping with: #{failures.join(' | ')}")
      return [ sections, body, meta ]
    end

    Rails.logger.info("[ProposalGenerator] repairing within #{[ left, ProposalRepair::TIMEOUT ].min}s, failed: #{failures.join(' | ')}")
    result = ProposalRepair.call(@posting, sections: sections, failures: failures, shape: shape,
                                           timeout: [ left, ProposalRepair::TIMEOUT ].min)
    Rails.logger.info("[ProposalGenerator] repaired #{result.changed.inspect} in #{result.duration_ms / 1000}s")

    # The repair writes prose, so it can bring a dash back in.
    repaired, rebuilt = tidy(result.sections, nil, fixed)
    [ repaired, rebuilt, merge_meta(meta, result.meta) ]
  rescue ProposalRepair::RepairError, ClaudeRun::Error => e
    Rails.logger.warn("[ProposalGenerator] repair failed (#{e.message}), shipping the draft as written")
    [ sections, body, meta ]
  end

  # An empty draft has nothing to ship and nothing to repair, so it is the one
  # case still worth a second whole generation.
  def redraft_empty(shape, meta)
    Rails.logger.warn("[ProposalGenerator] the draft came back empty, writing it once more")
    sections, body, again = serial_draft(shape)
    raise GenerationError, "the writer returned an empty proposal twice" if body.blank?

    [ sections, body, merge_meta(meta, again) ]
  end

  def tidy(sections, body, fixed)
    return [ sections, body ] if sections.blank?

    result = ProposalAutofix.call(sections)
    fixed.concat(result.fixed - fixed)
    [ result.sections, ProposalAssembler.call(result.sections) ]
  end

  def check(body, shape) = ProposalCheck.call(body, archetype: shape, posting: @posting)

  def over_limit?(checks) = checks[:characters].to_i > ProposalCheck::MAX_CHARS

  def elapsed_ms = ((Time.current - @started) * 1000).to_i

  def serial_draft(shape)
    raw, meta = run(prompt(shape))
    sections, body = split(raw)
    [ sections, body, meta.merge("mode" => "serial") ]
  end

  # Cost and turns add up across phases; the API duration is the longest leg,
  # because the writers overlap.
  def merge_meta(*metas)
    metas = metas.compact.map { |m| m.is_a?(Hash) ? m : {} }
    metas.reduce({}) do |acc, m|
      acc.merge(m) do |key, a, b|
        case key
        when "total_cost_usd" then (a.to_f + b.to_f).round(6)
        when "num_turns" then a.to_i + b.to_i
        when "duration_api_ms" then [ a.to_i, b.to_i ].max
        else b
        end
      end
    end
  end

  # The parts and the blob are the same text seen two ways. Assembling the body
  # from the parts rather than stripping markers out of the raw text is what
  # guarantees they cannot drift: what he copies is what he can edit.
  def split(raw)
    sectioner = ProposalSectioner.new(raw, posting: @posting)
    sections = sectioner.call

    return [ [], raw ] if sections.empty?

    Rails.logger.info("[ProposalGenerator] #{sections.size} parts, markers=#{sectioner.marked?}")
    [ sections, ProposalAssembler.call(sections) ]
  end

  # Upwork rejects a proposal over 5000 characters outright, and until now the
  # model was only ever told so when the post had questions buried in its
  # description. On every other post it optimised a word budget it had been
  # given while blowing a character limit it had never heard of.
  #
  # The cost was not a bad proposal, it was time: the check caught it after a
  # full generation, and the fix was a second full generation. Every letter
  # measured was inside its word budget; what pushed them over was the letter,
  # the answers and an unbudgeted projects block competing for the same 5000.
  def character_budget
    target = ProposalCheck::MAX_CHARS - CHARACTER_HEADROOM

    <<~TXT.strip

      CHARACTER LIMIT. Upwork rejects any proposal over #{ProposalCheck::MAX_CHARS} characters, so this is
      not a style note. Everything counts towards it together: the screening answers, the letter,
      the signature and the related projects block.
      Aim for #{target} characters. That leaves room to be wrong about the count.
      Bold Unicode costs TWO characters per glyph, so a heading of ten bold letters costs twenty.
      Use bold for section headings only, never for whole sentences.
      The related projects block gets at most #{MAX_PROJECTS} projects and about #{PROJECT_WORDS} words each.
      It is the first thing to cut when space is tight, because the letter is what wins the job.
    TXT
  end

  # Enough slack that a small miscount does not cost a whole second generation.
  CHARACTER_HEADROOM = 400

  # The projects block was the only part of the proposal with no budget at all,
  # and it grew to 172 words while the letter stayed honestly inside its range.
  MAX_PROJECTS = 3
  PROJECT_WORDS = 35

  def spec = @spec ||= ProposalSpec.render

  def prompt(shape)
    parts = []
    parts << "Write a real Upwork proposal for #{Profile.first_name}. Read CLAUDE.md, writing-voice.md, profile.yml, skills.yml and projects/_index.yml first, then follow the spec exactly."
    parts << ""
    parts << spec
    parts << ""
    parts << "---"
    parts << "THIS JOB"
    parts << ""
    parts << "Title: #{@posting.title}"
    parts << ""
    parts << @posting.description.to_s

    questions = @posting.screening_questions_list
    if questions.any?
      parts << ""
      parts << "SCREENING QUESTIONS. Answer each one, numbered, before the letter. The client sees these first."
      parts += questions.map.with_index(1) { |q, i| "#{i}. #{q}" }
      parts << ""
      parts << "Where one numbered question contains several questions, answer each of them."
    end

    parts << ""
    parts << "---"
    parts << "WHAT RADAR KNOWS ABOUT THIS CLIENT AND THE COMPETITION"
    parts += shape[:signals].map { |s| "- #{s}" }
    parts << ""
    parts << "THE OPENING DECIDES WHETHER THEY OPEN IT AT ALL."
    parts << "Two to three sentences, 45 words maximum: the hardest quantified proof you have that matches what THEY asked for, "\
             "then a phrase that opens a loop and promises what comes next. Deliver on that promise immediately as a list."
    parts << ProposalSpec.opening_model
    parts << "If the first line could fit 200 different jobs, it is too broad. Rewrite it."
    parts << "Do NOT open with a question. Do NOT open by restating their brief (\"You need\", \"You want\", \"The system you describe\"). "\
             "Do NOT open with their name, title or years."
    parts << "At most ONE question in the whole letter, placed late. A list of questions reads as an interview they are conducting rather than "\
             "a specialist who has already solved this."
    parts << "Make #{Profile.first_name} look formidable. The skills section must answer their requirement list point for point with specifics only someone "\
             "who shipped it would know: gem names, versions, patterns, tooling."
    parts << "Vary the wording, the projects and the skills every time. Do NOT vary the skeleton."
    parts << ""
    parts << "ARCHETYPE: #{@archetype.label} (#{shape[:name]})"
    target = ((shape[:words].min + shape[:words].max) / 2.0).round
    parts << "Letter budget: #{shape[:words].min} to #{shape[:words].max} words. Aim for #{target}."

    if questions.any?
      answers = shape[:answer_words]
      parts << "Answer budget: #{answers.min} to #{answers.max} words for ALL #{shape[:question_count]} answers together, " \
               "which is #{ProposalArchetype::ANSWER_WORDS.min} to #{ProposalArchetype::ANSWER_WORDS.max} words each. This is a hard limit."
      parts << "The answers do NOT reduce the letter budget. The letter is the pitch and must still hit its own range in full."
      parts << "Answer in prose, the way you would say it out loud. At most two bullets in any one answer. " \
               "A wall of bullets reads as machine-written and loses the job."
    end

    parts << character_budget

    if (inline = shape[:inline_questions]).any?
      parts << ""
      parts << "THE POST ASKS FOR THESE IN ITS DESCRIPTION. They are NOT screening questions:"
      parts += inline.map.with_index(1) { |q, i| "#{i}. #{q}" }
      parts << ""
      parts << "Upwork gives these no boxes of their own. Everything goes in the one cover letter textarea."
      parts << "So: answer them INSIDE the letter, in the post's order, and do NOT put them above it or use a ----- separator."
      parts << "The first 250 characters must still be the hook about their problem. If the client's preview reads \"1. My CV\", you have lost the job before they open it."
      parts << "#{ProposalArchetype::INLINE_ANSWER_WORDS.min} to #{ProposalArchetype::INLINE_ANSWER_WORDS.max} words per item. The letter budget above already includes them."
    end

    parts += planted_instructions

    if (lessons = Lesson.prompt_block(saved_search: @posting.saved_search, archetype: @archetype.label))
      parts << ""
      parts << "---"
      parts << lessons
    end

    if @template.present?
      parts << ""
      parts << "STRUCTURE: follow templates/#{@template}.md. Read it. It is the shape #{Profile.first_name} actually sends and wins with, " \
               "and it agrees with the spec. Do not flatten it into plain paragraphs."
    end

    if @feedback.present?
      parts << ""
      parts << "---"
      parts << "#{Profile.first_name} rejected the previous version. Previous version:"
      parts << @previous.to_s
      parts << ""
      parts << "Their feedback, apply it precisely:"
      parts << @feedback.to_s
    end

    parts << ""
    parts << "---"
    parts << output_contract(questions)
    parts.join("\n")
  end

  # Spec rule R7, made concrete. The check verifies the word afterwards; saying
  # it here is what keeps a miss from costing a repair.
  def planted_instructions
    reader = ProposalCheck.new("", archetype: {}, posting: @posting)
    lines = []

    if (word = reader.planted&.dig(:word))
      where = reader.planted[:at_start] ? "as the very first word of the cover letter" : "somewhere in the proposal, naturally"
      lines << "" << "PLANTED INSTRUCTION. The post asks for the word \"#{word}\" #{where}. Do exactly that, verbatim. Missing it is an instant reject."
    end

    if (bait = reader.bait).any?
      lines << "" << "The post plants #{bait.map { |w| %("#{w}") }.join(' and ')} for AI writers to use. A human leaves it out. Do NOT use it."
    end

    lines
  end

  # Farzam rewrites one part at a time: the opening, an answer, the skills
  # block. Naming the parts is what lets that happen without paying to
  # regenerate the nine parts that were already right.
  #
  # The names are deliberately NOT fixed. A scoped Rails migration and a vague
  # one-liner want different shapes, and forcing both into the same headings
  # would undo the thing that makes the proposals good.
  def output_contract(questions)
    <<~TXT.strip
      Output ONLY the finished proposal inside a single fenced block. No commentary before or after. Plain text inside the block.

      Divide it into named parts. Each part begins with a marker line of its own:

      === Name of the part | role ===

      The role is exactly one of: answer, letter, portfolio.
      - answer: one screening question answer. One part per question, in order.#{questions.any? ? "" : " This post has none, so use none."}
      - letter: a piece of the cover letter.
      - portfolio: the related projects block at the end.

      YOU choose the names of the letter parts, and you name them for THIS job. Opening, How I fit,
      My relevant skills, Ready to get started and Signature are a reasonable default set, but a post
      that wants a migration plan or a security review should have parts named for that. Different
      jobs having differently named parts is correct, not a mistake.

      Rules for the parts:
      - A name is a short label, under 60 characters, plain text, no bold glyphs.
      - Keep any bold Unicode heading inside the part's own text, where it already belongs.
      - Do NOT number the answers. Write the answer text only; the numbering is added afterwards.
      - Do NOT write ----- separator lines anywhere. The parts carry that now.
      - Each part must stand on its own well enough to be rewritten alone, and all of them read
        together must still be one proposal that flows. Both things, not one or the other.
    TXT
  end

  # One shared runner, so the timeout and kill behaviour cannot drift between
  # the generator, the rewriter and the distiller.
  def run(text)
    result = ClaudeRun.call(text, timeout: Radar.generation_timeout, model: Radar.writer_model, label: "proposal")
    [ ClaudeRun.fenced(result.text), result.meta ]
  rescue ClaudeRun::Error => e
    raise GenerationError, e.message
  end
end
