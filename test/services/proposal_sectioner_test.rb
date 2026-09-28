require "test_helper"

class ProposalSectionerTest < ActiveSupport::TestCase
  # Mathematical sans-serif bold, the alphabet his headings are written in.
  # Built rather than pasted, so a mistyped codepoint cannot pass for a bug.
  def self.bold(text)
    text.each_char.map { |c|
      case c
      when "A".."Z" then (0x1D5D4 + (c.ord - 65)).chr(Encoding::UTF_8)
      when "a".."z" then (0x1D5EE + (c.ord - 97)).chr(Encoding::UTF_8)
      else c
      end
    }.join
  end

  SKILLS = bold("My Relevant Skills").freeze
  EXAMPLES = bold("Examples of My Work").freeze

  def posting(questions: [])
    JobPosting.new(title: "Rails backend", upwork_id: "x#{rand(10_000)}",
                   description: "Build an API.", screening_questions: questions)
  end

  # --- the marked path, which is what a fresh generation produces ----------

  test "parses marker lines and keeps the writer's own part names" do
    raw = <<~TXT
      === What I have shipped | letter ===
      PadStats is a Rails 7 GraphQL API.

      === The migration risk | letter ===
      The risk is the double write.

      === Related projects | portfolio ===
      PadStats. See more at: http://padstats.com/
    TXT

    parts = ProposalSectioner.call(raw, posting: posting)

    assert_equal [ "What I have shipped", "The migration risk", "Related projects" ], parts.map(&:label)
    assert_equal %w[letter letter portfolio], parts.map(&:role)
    assert_equal "PadStats is a Rails 7 GraphQL API.", parts.first.body
  end

  test "an answer keeps no leading number, because the assembler owns numbering" do
    raw = <<~TXT
      === Q1: Rails upgrades | answer ===
      1. I upgrade a version at a time behind a flag.

      === Opening | letter ===
      PadStats is a Rails 7 GraphQL API.
    TXT

    parts = ProposalSectioner.call(raw, posting: posting(questions: [ "How do you upgrade Rails?" ]))

    assert_equal "I upgrade a version at a time behind a flag.", parts.first.body
    assert_equal "answer", parts.first.role
  end

  test "a letter part that opens on a numbered list keeps its number" do
    raw = <<~TXT
      === Opening | letter ===
      PadStats runs three services.

      === Plan | letter ===
      1. Freeze writes. 2. Backfill.
    TXT

    parts = ProposalSectioner.call(raw, posting: posting)
    assert_equal "1. Freeze writes. 2. Backfill.", parts.last.body
  end

  test "an unknown role still lands somewhere sensible" do
    raw = "=== Opening | preamble ===\nPadStats runs three services.\n\n=== Answer 1 | ? ===\nYes.\n"
    parts = ProposalSectioner.call(raw, posting: posting)

    assert_equal %w[letter answer], parts.map(&:role)
  end

  test "one stray marker is not a marked proposal" do
    raw = "=== not really ===\nJust a body with a line that looks like a marker."
    assert_not ProposalSectioner.new(raw, posting: posting).marked?
  end

  # --- the derived path, for the 145 proposals written before this ---------

  test "derives parts from a plain body with answers, letter and portfolio" do
    body = <<~TXT.strip
      1. Yes. Sera is a Rails 7.2 app.

      2. About four weeks.

      -----

      PadStats is the closest thing I have shipped. Here is how I fit:

      - Rails 7 and GraphQL in production.

      #{SKILLS}
      - Rails - versions 3 through 8.1.

      -----------------------------------------

      #{EXAMPLES}
      PadStats. See more at: http://padstats.com/
    TXT

    parts = ProposalSectioner.call(body, posting: posting(questions: [ "Rails?", "How long?" ]))

    assert_equal 2, parts.count { |p| p.role == "answer" }
    assert_equal 1, parts.count { |p| p.role == "portfolio" }
    assert parts.any? { |p| p.role == "letter" }
    assert_equal "Yes. Sera is a Rails 7.2 app.", parts.first.body
    assert_equal "1. Rails?", parts.first.label
  end

  test "a bold heading becomes a part, with a plain-text label" do
    body = "Opening line about PadStats.\n\n#{SKILLS}\n- Rails 8.1 in production."
    parts = ProposalSectioner.call(body, posting: posting)

    assert_equal [ "Opening", "My Relevant Skills" ], parts.map(&:label)
    assert parts.last.body.start_with?(SKILLS), "the heading stays inside its own part"
  end

  test "a body with no structure at all still yields one editable part" do
    parts = ProposalSectioner.call("One flat paragraph and nothing else.", posting: posting)

    assert_equal 1, parts.size
    assert_equal "Opening", parts.first.label
    assert_equal "letter", parts.first.role
  end

  test "an empty body yields nothing rather than an empty part" do
    assert_empty ProposalSectioner.call("", posting: posting)
  end

  # --- the round trip, which is the property that actually matters --------

  test "assembling the derived parts reproduces the proposal" do
    body = <<~TXT.strip
      1. Yes, Rails 7.2.

      2. Four weeks.

      -----

      PadStats is the closest thing I have shipped.

      #{SKILLS}
      - Rails 3 through 8.1.

      -----------------------------------------

      #{EXAMPLES}
      PadStats. See more at: http://padstats.com/
    TXT

    post = posting(questions: [ "Rails?", "How long?" ])
    rebuilt = ProposalAssembler.call(ProposalSectioner.call(body, posting: post))

    assert_equal body, rebuilt
  end

  test "the assembled body still splits the way ProposalParts expects" do
    parts = [
      ProposalSectioner::Section.new(label: "A1", role: "answer", body: "Yes, Rails 7.2."),
      ProposalSectioner::Section.new(label: "Opening", role: "letter", body: "PadStats is a Rails 7 API."),
      ProposalSectioner::Section.new(label: "Projects", role: "portfolio", body: "#{EXAMPLES}\nPadStats.")
    ]
    body = ProposalAssembler.call(parts)
    split = ProposalParts.new(body, has_questions: true)

    assert_equal "1. Yes, Rails 7.2.", split.answer_block
    assert_equal [ "Yes, Rails 7.2." ], split.answers_list
    assert_equal "PadStats is a Rails 7 API.", split.letter
  end

  test "the assembler numbers answers, so a rewrite that drops its number is safe" do
    parts = [
      ProposalSectioner::Section.new(label: "A1", role: "answer", body: "First."),
      ProposalSectioner::Section.new(label: "A2", role: "answer", body: "Second."),
      ProposalSectioner::Section.new(label: "Opening", role: "letter", body: "Body.")
    ]

    assert_equal "1. First.\n\n2. Second.\n\n-----\n\nBody.", ProposalAssembler.call(parts)
  end

  test "no separator is emitted when there are no answers" do
    parts = [ ProposalSectioner::Section.new(label: "Opening", role: "letter", body: "Body.") ]

    assert_equal "Body.", ProposalAssembler.call(parts)
  end
end
