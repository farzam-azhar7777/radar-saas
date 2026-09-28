# config/proposal_spec.md, rendered for the person this install belongs to.
#
# The spec is research about what wins on Upwork, and that part is anyone's.
# Five places in it were one freelancer's: his real opening, his name, his
# standing, his signature and his stack. Those are {{placeholders}} now,
# filled from the profile and the career folder.
module ProposalSpec
  PATH = Rails.root.join("config", "proposal_spec.md")

  # Shown when the person has not given an opening of their own. Brackets, not
  # an invented example: a made-up product in the prompt is a made-up product
  # waiting to appear in a real proposal.
  SKELETON = "[Live product name] is the closest thing to [what they are building] I have shipped: " \
             "[what it is, in their terms], where I [the hard number: commits, users, uptime, revenue] " \
             "and wired [their stack, named line for line]."

  module_function

  def render(profile = Profile.current)
    vars = {
      "name" => profile.first_name,
      "opening_example" => opening_example(profile),
      "standing_clause" => standing_clause(profile),
      "signature" => profile.signature_text.presence || profile.first_name,
      "skill_examples" => skill_examples
    }
    PATH.read.gsub(/\{\{(\w+)\}\}/) { vars.fetch(Regexp.last_match(1)) }
  end

  # Just the named section, for callers that only need part of the spec.
  def section(heading, profile = Profile.current)
    render(profile)[/^## #{Regexp.escape(heading)}$.*?(?=^## |\z)/m].to_s.strip
  end

  def opening_example(profile)
    if profile.winning_opening.present?
      context = profile.winning_opening_context.present? ? " #{profile.winning_opening_context.strip}" : ""
      "Real example, the one #{profile.first_name} actually sent#{context}:\n\n#{quote(%("#{profile.winning_opening.strip}"))}"
    else
      "The shape, with brackets for what comes from the project files. Fill every bracket from " \
        "#{profile.first_name}'s real work, never from this example:\n\n#{quote(%("#{SKELETON}"))}"
    end
  end

  # The one line the generator's prompt uses to show what an opening looks like.
  def opening_model(profile = Profile.current)
    if profile.winning_opening.present?
      "Model it on this, which is a real opening #{profile.first_name} sent and used: \"#{profile.winning_opening.strip}\""
    else
      "Model it on this shape, filling every bracket from the project files: \"#{SKELETON}\""
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
