require "test_helper"

class PersonalLayoutTest < ActiveSupport::TestCase
  LAYOUT = "Plain prose. 𝗘𝘅𝗮𝗺𝗽𝗹𝗲𝘀 𝗼𝗳 𝗠𝘆 𝗪𝗼𝗿𝗸 just before the sign-off.\n\nRegards,\nAda".freeze
  EXAMPLES = "𝗘𝘅𝗮𝗺𝗽𝗹𝗲𝘀 𝗼𝗳 𝗠𝘆 𝗪𝗼𝗿𝗸\n\n𝗣𝗮𝗱𝗦𝘁𝗮𝘁𝘀 - A Rails 7 API.\nStack included: Rails\nSee more at: https://padstats.io".freeze

  def section(label, role, body) = ProposalSectioner::Section.new(label: label, role: role, body: body)

  def with_layout
    CareerFolder.write(ProposalSpec::LAYOUT_FILE, LAYOUT)
    yield
  ensure
    FileUtils.rm_f(Radar.career_path.join(ProposalSpec::LAYOUT_FILE))
  end

  test "without a layout of their own, the shared structure stands" do
    text = ProposalSpec.render
    assert_includes text, "## The structure that wins the work"
    assert_not ProposalSpec.personal_layout?
  end

  test "a layout in the career folder replaces the shared structure and wins over it" do
    with_layout do
      text = ProposalSpec.render
      assert_not_includes text, "## The structure that wins the work"
      assert_not_includes text, "𝗥𝗘𝗟𝗔𝗧𝗘𝗗 𝗣𝗥𝗢𝗝𝗘𝗖𝗧𝗦"
      assert_includes text, "## Layout\n\n#{LAYOUT}"
      assert_includes text, "this layout wins"
      assert_includes text, "## Voice", "the rest of the spec is kept"
    end
  end

  test "with a layout, the examples go just before the sign-off with no rule" do
    with_layout do
      body = ProposalAssembler.call([ section("Opening", "letter", "PadStats is a Rails 7 API."),
                                      section("Sign-off", "letter", "Regards,\nAda"),
                                      section("Examples", "portfolio", EXAMPLES) ])

      assert_equal "PadStats is a Rails 7 API.\n\n#{EXAMPLES}\n\nRegards,\nAda", body
      assert_no_match ProposalAssembler::PORTFOLIO_RULE, body
    end
  end

  test "without a layout, the examples still follow the letter behind a rule" do
    body = ProposalAssembler.call([ section("Opening", "letter", "PadStats."), section("Sign-off", "letter", "Ada"),
                                    section("Examples", "portfolio", EXAMPLES) ])
    assert_equal "PadStats.\n\nAda\n\n#{ProposalAssembler::PORTFOLIO_RULE}\n\n#{EXAMPLES}", body
  end

  test "the letter is measured without an examples block written inside it" do
    body = "PadStats is a Rails 7 API, and I wired its Stripe billing.\n\n#{EXAMPLES}\n\nRegards,\nAda"
    assert_equal "PadStats is a Rails 7 API, and I wired its Stripe billing.", ProposalParts.new(body).letter
  end
end
