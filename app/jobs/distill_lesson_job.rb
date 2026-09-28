# Turns one piece of raw feedback into a durable writing rule, so the same
# correction never has to be given twice. Runs Claude with read-only tools
# inside the career folder so it can see the voice guide while deciding.
class DistillLessonJob < ApplicationJob
  queue_as :generation

  def perform(feedback)
    feedback.update_columns(outcome: Feedback::PENDING, outcome_note: nil)

    archetype = feedback.proposal&.archetype
    existing = Lesson.for(saved_search: feedback.saved_search, archetype: archetype).pluck(:body)
    text = ask(prompt(feedback, existing, archetype))
    return failed!(feedback, "The distiller returned nothing. It may have timed out.") if text.blank?

    parsed = parse(text)
    return failed!(feedback, "The distiller's answer could not be read as JSON.") if parsed.nil?

    # A skip is usually the right call, most often because an existing rule
    # already covers it. It used to be invisible, which made a correct decision
    # indistinguishable from a silent failure.
    return skipped!(feedback, parsed["reason"]) if parsed["skip"]

    lesson = Lesson.create!(
      saved_search: parsed["scope"] == "search" ? feedback.saved_search : nil,
      archetype: parsed["scope"] == "archetype" ? archetype : nil,
      body: parsed["lesson"],
      source_feedback: feedback.body
    )
    feedback.update_columns(outcome: Feedback::LEARNED, lesson_id: lesson.id, outcome_note: nil)
  rescue StandardError => e
    Rails.logger.error("[DistillLessonJob] #{e.class}: #{e.message}")
    failed!(feedback, "#{e.class}: #{e.message.to_s.first(200)}")
  end

  private

  def failed!(feedback, note)
    feedback.update_columns(outcome: Feedback::FAILED, outcome_note: note)
    nil
  end

  def skipped!(feedback, reason)
    feedback.update_columns(
      outcome: Feedback::SKIPPED,
      outcome_note: reason.presence || "Judged too specific to this one job to apply generally."
    )
    nil
  end

  def prompt(feedback, existing, archetype)
    <<~TXT
      #{Profile.first_name} gave feedback on a generated Upwork proposal. Turn it into ONE durable
      writing rule for future proposals, or decide it is too one-off to be worth keeping.

      Job title: #{feedback.job_posting&.title}
      Job category: #{feedback.saved_search&.name}
      Proposal archetype: #{archetype || "unknown"} (the shape it was written in)

      Their feedback:
      #{feedback.body}

      Rules already learned, do not duplicate these:
      #{existing.map { |e| "- #{e}" }.join("\n").presence || "(none yet)"}

      Reply with ONLY a JSON object in a fenced block, no prose:
      {"skip": false, "scope": "global" | "archetype" | "search", "lesson": "one imperative sentence",
       "reason": "one sentence, only when skip is true"}

      Use "skip": true when the feedback is specific to this one job and would be
      wrong to apply generally, or when a rule above already covers it. When you
      skip, "reason" MUST say why in one plain sentence, and where it already
      covers it, quote the rule that does. #{Profile.first_name} reads these, and a skip with no
      reason is indistinguishable from the thing being broken.
      Use "archetype" when the rule is about how this SHAPE of proposal should be
      written, for example how short a high-competition proposal must be.
      Use "search" when it only makes sense for this category of job.
      Use "global" when it is about their voice or format everywhere.
      The lesson must be an instruction a writer can follow, not a description.
    TXT
  end

  def ask(text)
    ClaudeRun.call(text, timeout: 300, label: "distil lesson").text
  rescue ClaudeRun::Error => e
    Rails.logger.warn("[DistillLessonJob] #{e.message}")
    nil
  end

  def parse(text)
    block = text[/```(?:json)?\s*\n(.*?)```/m, 1] || text
    json = JSON.parse(block.strip)
    return nil if json["lesson"].to_s.strip.blank? && !json["skip"]

    json
  rescue JSON::ParserError
    nil
  end
end
