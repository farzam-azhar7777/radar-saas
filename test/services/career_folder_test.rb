require "test_helper"

# The proposal engine reads a folder of plain files. These tests pin what the
# wizard writes into it, because a missing or malformed file there does not
# fail loudly: it just makes every proposal worse.
class CareerFolderTest < ActiveSupport::TestCase
  setup { reset_career! }
  teardown { install_career_fixture! }

  def ada
    Profile.new(full_name: "Ada Lovelace", title: "Rails Developer", country: "United Kingdom", city: "London",
                timezone: "Europe/London", hourly_rate: 60, hours_per_week: 30, response_time: "same day",
                github_url: "https://github.com/ada", github_note: "Most of my work is in private client repos.",
                upwork_url: "https://www.upwork.com/freelancers/ada", credentials_line: "Top Rated",
                languages: "English, French")
  end

  test "ensure creates the folders and installs the starter templates once" do
    CareerFolder.ensure!

    %w[projects templates applications].each { |d| assert Radar.career_path.join(d).directory?, d }
    assert_equal 4, CareerData.instance.templates.size

    edited = Radar.career_path.join("templates", "basic-default.md")
    edited.write("mine now")
    CareerFolder.ensure!
    assert_equal "mine now", edited.read, "a template the person edited must never be overwritten"
  end

  test "no starter template mentions another product" do
    Dir[CareerFolder::SOURCE.join("templates", "*.md")].each do |f|
      assert_no_match(/PouncerAI/, File.read(f), File.basename(f))
    end
  end

  test "profile.yml carries what the generator reads" do
    CareerFolder.write_profile!(ada)
    yaml = YAML.safe_load_file(Radar.career_path.join("profile.yml"))

    assert_equal "Ada Lovelace", yaml["name"]
    assert_equal "Rails Developer", yaml["title"]
    assert_equal "London, United Kingdom", yaml["location"]
    assert_equal 60, yaml.dig("rates", "hourly_usd")
    assert_equal "https://github.com/ada", yaml.dig("contact", "github")
    assert_equal [ "English", "French" ], yaml["languages_spoken"]
  end

  test "CLAUDE.md states the rules and the facts, and only facts that exist" do
    CareerFolder.write_profile!(ada)
    md = Radar.career_path.join("CLAUDE.md").read

    assert_includes md, "Never invent"
    assert_includes md, "**Name:** Ada Lovelace"
    assert_includes md, "Sign as Ada."
    assert_includes md, "Most of my work is in private client repos."
    assert_includes md, "never link it inside a proposal"
    assert_not_includes md, "LinkedIn", "no LinkedIn was given, so none is mentioned"
    assert_not_includes md, "Farzam"
  end

  test "CLAUDE.md with no links says not to invent any" do
    CareerFolder.write_profile!(Profile.new(full_name: "Bo Diddley", title: "Dev"))
    assert_includes Radar.career_path.join("CLAUDE.md").read, "None on file. Do not invent or promise any."
  end

  test "the voice file quotes their samples and their winning opening verbatim" do
    ada_voice = ada.tap { |p|
      p.voice_samples = [ "Hi Sam,\n\nShipped the billing fix. Took an hour." ]
      p.winning_opening = "Ledgerline is the closest thing to your tool I have shipped."
      p.winning_opening_context = "for a billing role"
    }
    CareerFolder.write_voice!(ada_voice)
    md = Radar.career_path.join("writing-voice.md").read

    assert_includes md, "> Ledgerline is the closest thing to your tool I have shipped."
    assert_includes md, "Context: for a billing role"
    assert_includes md, "> Hi Sam,\n>\n> Shipped the billing fix. Took an hour."
  end

  test "with no samples the voice file still gives plain guidance rather than nothing" do
    CareerFolder.write_voice!(ada)
    assert_includes Radar.career_path.join("writing-voice.md").read, "No samples of Ada's writing yet."
  end

  test "the index keeps only the fields matching reads" do
    CareerFolder.write_index!([ { "file" => "a.yml", "name" => "A", "one_liner" => "x", "tags" => [ "rails" ],
                                  "relevance" => [ "payments" ], "secret" => "no" } ])
    entry = YAML.safe_load_file(Radar.career_path.join("projects", "_index.yml"))["projects"].first

    assert_equal %w[file name one_liner tags relevance], entry.keys
    assert_equal [ "rails", "payments" ], CareerData.instance.project_terms
  end

  test "career data notices a file written by another process" do
    CareerFolder.write_skills!("frameworks" => [ { "name" => "Ruby on Rails" } ])
    assert_includes CareerData.instance.skill_terms, "ruby on rails"

    sleep 0.01
    CareerFolder.write_skills!("frameworks" => [ { "name" => "Django" } ])
    assert_includes CareerData.instance.skill_terms, "django"
    assert_not_includes CareerData.instance.skill_terms, "ruby on rails"
  end
end
