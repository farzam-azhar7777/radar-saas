# config/proposal_spec.md, rendered for the person this install belongs to.
#
# The spec is research about what wins on Upwork, and that part is anyone's.
# Five places in it were one freelancer's: his real opening, his name, his
# standing, his signature and his stack. Those are {{placeholders}} now,
# filled from the profile and the career folder.
module ProposalSpec
  PATH = Rails.root.join("config", "proposal_spec.md")

  # Shown when the person has not given an opening of their own. A description,
  # not a sentence to fill in: the fill-in sentence this replaced opened 65 of
  # 95 proposals word for word, and a client who saw two of them saw a template.
  NO_EXAMPLE = "Name the project from the files that is closest to this post, say in plain words " \
               "what you built in it, and why that is the same problem they have."

  module_function

  def render(profile = Profile.current)
    vars = {
      "name" => profile.first_name,
      "opening_example" => opening_example(profile),
      "standing_clause" => standing_clause(profile),
      "signature" => profile.signature_text.presence || profile.first_name,
      "skill_examples" => skill_examples
    }
    text = PATH.read.gsub(/\{\{(\w+)\}\}/) { vars.fetch(Regexp.last_match(1)) }
    personal_layout? ? with_layout(text, layout) : text
  end

  LAYOUT_FILE = "proposal-format.md".freeze
  SHARED_LAYOUT_SECTIONS = [ "The structure that wins the work", "Shape" ].freeze

  def layout = CareerFolder.read(LAYOUT_FILE).to_s.strip.presence

  def personal_layout? = layout.present?

  def with_layout(text, layout)
    shared = SHARED_LAYOUT_SECTIONS.reduce(text) { |t, heading| t.sub(/^## #{Regexp.escape(heading)}$.*?(?=^## |\z)/m, "") }
    "#{shared.rstrip}\n\n## Layout\n\n#{layout}\n\nWhere this layout disagrees with anything above, this layout wins.\n"
  end

  # Just the named section, for callers that only need part of the spec.
  def section(heading, profile = Profile.current)
    render(profile)[/^## #{Regexp.escape(heading)}$.*?(?=^## |\z)/m].to_s.strip
  end

  def opening_example(profile)
    if profile.winning_opening.present?
      context = profile.winning_opening_context.present? ? " #{profile.winning_opening_context.strip}" : ""
      "Real example, the one #{profile.first_name} actually sent#{context}:\n\n#{quote(%("#{profile.winning_opening.strip}"))}\n\n" \
        "Take its directness, never its wording or sentence shape."
    else
      NO_EXAMPLE
    end
  end

  # The one line the generator's prompt uses to say what an opening is. A real
  # opening is shown for its tone only, because copying its shape is the formula.
  def opening_model(profile = Profile.current)
    if profile.winning_opening.present?
      "This is a real opening #{profile.first_name} sent: \"#{profile.winning_opening.strip}\" " \
        "Take its directness, never its wording or sentence shape."
    else
      NO_EXAMPLE
    end
  end

  def standing_clause(profile)
    if profile.credentials_line.present?
      "it is the thing that made #{profile.first_name} #{profile.credentials_line.strip.sub(/\.\z/, '')}"
    else
      "it is the shape that gets a proposal opened and answered"
    end
  end

  # Real names from their own stack, so the example of "specifics" is theirs.
  def skill_examples
    names = CareerData.instance.example_tools(6)
    base = "library names, versions, patterns and tooling"
    names.any? ? "#{base}, such as #{names.to_sentence}" : base
  end

  def quote(text)
    wrap(text, 76).map { |line| "> #{line}" }.join("\n")
  end

  def wrap(text, width)
    text.split(/\s+/).each_with_object([ +"" ]) { |word, lines|
      if lines.last.empty? then lines.last << word
      elsif lines.last.length + 1 + word.length <= width then lines.last << " " << word
      else lines << word.dup
      end
    }
  end
end
