# Phase two: turn the plan into prose, several parts at once.
#
# Roughly all of a generation's wall clock is token generation, and tokens come
# out in series. Writing five groups concurrently makes the wall clock the
# slowest group rather than the sum of all of them.
#
# The thing that makes this safe is that no writer is blind. Every one receives
# the whole plan, so it knows the argument, the hook it must answer or honour,
# and which evidence belongs to somebody else. Writers see facts, not files:
# everything about Farzam's history was decided in the plan, so nobody spends
# turns re-reading the career repo.
class ParallelProposalWriter
  TIMEOUT = Integer(ENV.fetch("RADAR_WRITER_TIMEOUT", 420))

  # Five at once at the very most, and usually fewer, because only the groups
  # the plan actually used are written.
  MAX_CONCURRENCY = Integer(ENV.fetch("RADAR_WRITER_CONCURRENCY", 5))

  class WriteError < StandardError; end

  Result = Struct.new(:sections, :duration_ms, :meta, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(posting, plan:, shape:, model: nil)
    @posting = posting
    @plan = plan
    @shape = shape
    @model = model
  end

  def call
    started = Time.current
    groups = grouped_parts
    raise WriteError, "the plan produced no parts to write" if groups.empty?

    results = run_concurrently(groups)
    sections = order(results)
    raise WriteError, "no part came back with any text" if sections.empty?

    Result.new(sections: sections, duration_ms: ((Time.current - started) * 1000).to_i,
               meta: merge_meta(results))
  end

  private

  def planned_parts = Array(@plan["parts"])

  # Group order is the order the parts appear in the finished proposal, so a
  # plan that forgets to order its parts still assembles sensibly.
  def grouped_parts
    planned_parts
      .group_by { |p| ProposalPlan::GROUPS.include?(p["group"].to_s) ? p["group"].to_s : "argue" }
      .sort_by { |group, _| ProposalPlan::GROUPS.index(group) || 99 }
  end

  # Threads, not processes: each writer spends its whole life waiting on a
  # subprocess, so the GVL is released and they really do run at the same time.
  def run_concurrently(groups)
    groups.each_slice(MAX_CONCURRENCY).flat_map do |slice|
      slice.map { |group, parts| Thread.new { write(group, parts) } }.map(&:value)
    end
  end

  def write(group, parts)
    run = ClaudeRun.call(prompt_for(group, parts), timeout: TIMEOUT, model: @model, label: "writer:#{group}")
    # min_markers: 1, because a group with a single part emits a single marker
    # and that is the whole of its output, not a stray line to be second-guessed.
    sections = ProposalSectioner.call(ClaudeRun.fenced(run.text), posting: @posting, min_markers: 1)
    { group: group, sections: sections, meta: run.meta }
  rescue ClaudeRun::Error => e
    # One writer failing must not lose the other four. The caller decides
    # whether what came back is enough to be worth keeping.
    Rails.logger.error("[ParallelProposalWriter] #{group}: #{e.message}")
    { group: group, sections: [], meta: {}, error: e.message }
  end

  def order(results)
    results
      .sort_by { |r| ProposalPlan::GROUPS.index(r[:group]) || 99 }
      .flat_map { |r| r[:sections] }
  end

  def merge_meta(results)
    metas = results.map { |r| r[:meta] || {} }
    {
      "total_cost_usd" => metas.sum { |m| m["total_cost_usd"].to_f }.round(6),
      "num_turns" => metas.sum { |m| m["num_turns"].to_i },
      "duration_api_ms" => metas.map { |m| m["duration_api_ms"].to_i }.max,
      "writers" => results.size,
      "writer_errors" => results.filter_map { |r| r[:error] }.presence
    }.compact
  end

  # --- the prompt each writer gets ----------------------------------------

  def prompt_for(group, parts)
    lines = []
    lines << "You are writing PART of an Upwork proposal for #{Profile.first_name}. Four other writers are writing the other " \
             "parts at the same time, from the same plan. Write only the parts assigned to you below."
    lines << "Everything you need about their history is in the plan. Do not go looking for more: if a fact is not " \
             "in the plan it does not go in the proposal."
    lines << ""
    lines << "---"
    lines << "THE JOB"
    lines << "Title: #{@posting.title}"
    lines << ""
    lines << @posting.description.to_s.truncate(2500)
    lines << ""
    lines << "---"
    lines << "THE PLAN. This is the shared contract. Honour it exactly."
    lines << JSON.pretty_generate(@plan)
    lines << ""
    lines << "---"
    lines << "YOUR PARTS (#{group}), in this order:"
    parts.each_with_index do |p, i|
      lines << "#{i + 1}. #{p['label']}  [role: #{p['role']}, about #{p['words']} words]"
      lines << "   #{p['brief']}"
    end
    lines << ""
    lines << group_rules(group)
    lines << ""
    lines << voice
    lines << ""
    lines << "---"
    lines << output_contract(parts)
    lines.join("\n")
  end

  def group_rules(group)
    case group
    when "open"
      "This is the only thing the client sees before deciding whether to open the proposal. Lead with the " \
      "plan's opening project and its proof, in plain text with no bold glyphs, and end on the plan's hook " \
      "word for word or close to it. Then deliver the hook_list immediately. Two to three sentences before " \
      "the list, 45 words at most. Never open with a question, never restate their brief, never their name or years."
    when "argue"
      "This is what makes #{Profile.first_name} look formidable. Walk their requirement list and answer it point for point using " \
      "the plan's skills mapping, with the specifics only someone who shipped it would know. Keep the bold " \
      "Unicode heading on the skills section. Do not re-use the opening's project as though it were new."
    when "close"
      "A defined next step, their availability and response time, then the signature block. Low friction: make " \
      "replying easy. Never a stock sign-off."
    when "portfolio"
      "The related projects block, using exactly the projects the plan chose, most relevant first. Each one: " \
      "title, one line of what it is, \"Created using ...\", \"See more at: URL\". At most " \
      "#{ProposalGenerator::MAX_PROJECTS}, about #{ProposalGenerator::PROJECT_WORDS} words each. This is the " \
      "first thing cut when space is tight, so keep it tight already."
    when "answers"
      "These are read before the letter, so they set the tone. Answer the actual question in the first " \
      "sentence, in prose, the way they would say it out loud. #{ProposalArchetype::ANSWER_WORDS.min} to " \
      "#{ProposalArchetype::ANSWER_WORDS.max} words each, at most two bullets in any one answer, and do NOT " \
      "number them. Say plainly where something is outside their experience."
    else
      ""
    end
  end

  def voice
    <<~TXT.strip
      VOICE
      - Hyphens. Never em dashes or en dashes.
      - Contractions. Vary sentence length. Some sentences very short.
      - Every claim carries a specific: a project name, a number, a version, a tool.
      - Never: #{ProposalCheck::BANNED.join(', ')}.
      - Never link their Upwork profile. Upwork attaches it automatically.
      - Bold Unicode for section headings only, never in the first 250 characters, and it costs
        two characters per glyph.
    TXT
  end

  def output_contract(parts)
    <<~TXT.strip
      Output ONLY your parts, inside a single fenced block. No commentary before or after.
      Begin each part with a marker line of its own, using the label exactly as given above:

      #{parts.map { |p| "=== #{p['label']} | #{p['role']} ===" }.join("\n")}

      Write every one of those parts, in that order, and nothing else. No ----- separator lines.
    TXT
  end
end
