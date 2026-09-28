# Phase one of writing a proposal: decide the facts before anyone writes prose.
#
# Writing the whole proposal in one pass is slow because roughly all of the
# wall clock is token generation, and it is generated in series. Writing the
# parts in parallel is fast, but parts written blind to each other produce a
# proposal that reads like five people wrote it: the opening promises a list
# nobody delivers, two sections claim the same project, the portfolio repeats
# what the letter already said.
#
# This is the fix. One small call decides the argument, which project anchors
# which section, and which of the client's requirements maps to which piece of
# evidence. Every writer then gets the whole plan, so none of them is blind.
# The plan is the coherence contract, and it is cheap because its output is a
# short object rather than 700 words of prose.
class ProposalPlan
  # Deciding is a smaller job than writing, and it holds up everything else,
  # so it gets a tighter leash than a full generation.
  # 300s was too tight and the first live run hit it. The plan now gets the
  # career index inlined instead of exploring for it, so this is headroom
  # rather than a budget it is expected to spend.
  TIMEOUT = Integer(ENV.fetch("RADAR_PLAN_TIMEOUT", 480))

  # Which writer takes each part. Fixed, small, and chosen so that parts which
  # depend on each other most tightly are written by the same call.
  GROUPS = %w[open argue close portfolio answers].freeze

  class PlanError < StandardError; end

  Result = Struct.new(:data, :duration_ms, :meta, keyword_init: true)

  def self.call(...) = new(...).call

  def initialize(posting, shape:, feedback: nil, previous: nil)
    @posting = posting
    @shape = shape
    @feedback = feedback
    @previous = previous
  end

  def call
    run = ClaudeRun.call(prompt, timeout: TIMEOUT, model: self.class.model, label: "proposal plan")
    data = sanitise(parse(run.text))
    raise PlanError, "the plan came back with no parts" if Array(data["parts"]).empty?

    Result.new(data: data, duration_ms: run.duration_ms, meta: run.meta)
  end

  private

  # A plan is a model's output, so it gets checked before anything is built on
  # it. The failure that made this necessary: on a post with no screening
  # questions the planner produced a part with role "answer" anyway. The
  # assembler dutifully put it above a ----- separator, ProposalParts then read
  # that as the answer block, and a 500-word letter measured as 74 words. The
  # checks failed on a number that was never real, and the repair spent 268
  # seconds fixing prose that was fine.
  #
  # An answer with nothing to answer is letter content that was mislabelled, so
  # it is relabelled rather than thrown away.
  def sanitise(data)
    parts = Array(data["parts"]).select { |p| p.is_a?(Hash) }

    parts.each do |part|
      role = part["role"].to_s
      part["role"] = "letter" unless ProposalSectioner::ROLES.include?(role)

      next unless part["role"] == "answer" && questions.empty?

      Rails.logger.warn("[ProposalPlan] dropped an answer role from #{part['label'].inspect}: this post has no screening questions")
      part["role"] = "letter"
      part["group"] = "argue" unless ProposalPlan::GROUPS.include?(part["group"].to_s) && part["group"] != "answers"
    end

    # More answers than questions is the same mistake by another route.
    if questions.any?
      answers = parts.select { |p| p["role"] == "answer" }
      answers.drop(questions.size).each { |p| p["role"] = "letter"; p["group"] = "argue" }
    end

    data.merge("parts" => parts)
  end

  # The planner decides facts and shape. It does not write a sentence, so the
  # half of the spec about voice, banned phrasing and how to word an answer is
  # pure reasoning load for it, and the writers get that part instead.
  PLANNING_SECTIONS = [
    "What the client actually sees, in order",
    "Rules",
    "Archetypes",
    "The structure that wins the work"
  ].freeze

  def spec
    @spec ||= begin
      full = ProposalSpec.render
      wanted = full.split(/^## /).select { |chunk| PLANNING_SECTIONS.any? { |s| chunk.start_with?(s) } }
      wanted.any? ? wanted.map { |c| "## #{c}".rstrip }.join("\n\n") : full
    end
  end

  # Planning is decision-making against a rigid schema rather than prose, so it
  # is the one phase where a faster model costs nothing in voice. Left unset it
  # uses whatever the CLI is configured with.
  def self.model = ENV["RADAR_PLAN_MODEL"].presence

  def questions = @posting.screening_questions_list

  def prompt
    parts = []
    parts << "You are planning an Upwork proposal for #{Profile.first_name}. You are NOT writing it yet."
    parts << "Your job is to decide the facts. Other writers will turn your plan into prose in parallel, and they " \
             "will see nothing about their history except what you put here, so anything you leave out cannot " \
             "appear in the proposal."
    # His profile, skills and project index are inlined below rather than read.
    # Exploring the repo cost this call more than five minutes before it wrote
    # a word, which is the whole reason a proposal used to take so long.
    parts << "Everything you need is below: their profile, their skills, the index of every project, and the full " \
             "detail of the projects that match this job. Do NOT read any files. Going looking for them is what " \
             "made this call take seven minutes, and there is nothing there you have not been given."
    parts << ""
    parts << "---"
    parts << "WHAT #{Profile.first_name} HAS DONE"
    parts << CareerData.instance.briefing
    parts << ""
    parts << "THE PROJECTS THAT MATCH THIS JOB, IN FULL"
    parts << CareerData.instance.projects_for(@posting)
    parts << ""
    parts << spec
    parts << ""
    parts << "---"
    parts << "THIS JOB"
    parts << "Title: #{@posting.title}"
    parts << ""
    parts << @posting.description.to_s

    if questions.any?
      parts << ""
      parts << "SCREENING QUESTIONS, answered in their own boxes above the letter. Plan exactly #{questions.size} " \
               "part(s) with role \"answer\", one per question, and no more:"
      parts += questions.map.with_index(1) { |q, i| "#{i}. #{q}" }
    else
      parts << ""
      parts << "THIS POST HAS NO SCREENING QUESTIONS. Do NOT plan any part with role \"answer\" and do not use " \
               "the \"answers\" group. Everything goes in the cover letter."
    end

    if (inline = @shape[:inline_questions]).any?
      parts << ""
      parts << "THE DESCRIPTION ALSO ASKS FOR THESE. They have no boxes of their own, so they are answered " \
               "inside the letter, never above it:"
      parts += inline.map.with_index(1) { |q, i| "#{i}. #{q}" }
    end

    parts << ""
    parts << "WHAT RADAR KNOWS ABOUT THIS CLIENT AND THE COMPETITION"
    parts += @shape[:signals].map { |s| "- #{s}" }
    parts << ""
    # Aim for the middle, not the ceiling. A plan that budgets the parts up to
    # the top of the range leaves no room for a writer to run twenty words long,
    # and a twenty-word overrun costs a repair pass of about four minutes.
    target = ((@shape[:words].min + @shape[:words].max) / 2.0).round
    parts << "ARCHETYPE #{@shape[:key]} (#{@shape[:name]}). The letter must land between #{@shape[:words].min} and " \
             "#{@shape[:words].max} words. Budget the parts to total about #{target}, not the maximum: a writer " \
             "running slightly long must still leave the whole inside the range."
    parts << "Whole proposal must fit #{ProposalCheck::MAX_CHARS} characters. Aim for #{ProposalCheck::MAX_CHARS - 400}."

    if (lessons = Lesson.prompt_block(saved_search: @posting.saved_search, archetype: @shape[:key]))
      parts << ""
      parts << lessons
    end

    if @feedback.present?
      parts << ""
      parts << "#{Profile.first_name} rejected the previous version. Their feedback, plan around it precisely:"
      parts << @feedback.to_s
      parts << ""
      parts << "Previous version:"
      parts << @previous.to_s.truncate(2500)
    end

    parts << ""
    parts << "---"
    parts << schema
    parts.join("\n")
  end

  def schema
    <<~TXT.strip
      Output ONLY a JSON object in a single fenced block. No prose before or after.

      {
        "angle": "one sentence: the argument this proposal makes, in #{Profile.first_name}'s favour",
        "opening": {
          "project": "the real client-facing product name that anchors the first line",
          "proof": "the hard number or fact that makes it undeniable",
          "hook": "the exact phrase that ends the opening and promises what comes next"
        },
        "hook_list": ["the 2 to 4 things the hook promises, one line each, in order"],
        "skills": [
          {"requirement": "a requirement THEY listed, in their words",
           "evidence": "the gem, version, pattern or tool that proves they have done it"}
        ],
        "projects": ["the 2 or 3 real products for the related-projects block, most relevant first"],
        "answers": [
          {"question": "their screening question", "answer_in_one_line": "the direct answer",
           "proof": "the one project and detail that backs it"}
        ],
        "parts": [
          {"label": "what this part is called, your choice, under 60 characters",
           "role": "answer | letter | portfolio",
           "group": "open | argue | close | portfolio | answers",
           "words": 45,
           "brief": "what this part must say, and what it must NOT repeat from other parts"}
        ]
      }

      Rules for the plan:
      - Name REAL client-facing products, never repo, folder or service names.
      - Never invent a project, number, client or date. If you did not read it in the files, leave it out.
      - Every project appears in at most one of: the opening, the argument, the projects block.
        Say so explicitly in each brief, so no two writers spend the same evidence twice.
      - "group" decides which writer takes the part. Parts that depend on each other most
        must share a group, because only they are written together.
        open = the opening and the list its hook promises.
        argue = the industry fit and the skills section.
        close = the defined next step, availability, and the signature.
        portfolio = the related projects block.
        answers = the screening answers, one part each.
      - The "words" for all letter parts together must land inside the letter budget above.
      - You choose the part names, for THIS job. Different jobs having differently named
        parts is correct. Do not force a generic set of headings onto a specific post.
      - The opening must not be a question, must not restate their brief, and must not
        start with their name, title or years.
    TXT
  end

  def parse(text)
    json = JSON.parse(ClaudeRun.fenced(text))
    raise PlanError, "the plan was not an object" unless json.is_a?(Hash)

    json
  rescue JSON::ParserError => e
    raise PlanError, "the plan was not valid JSON: #{e.message}"
  end
end
