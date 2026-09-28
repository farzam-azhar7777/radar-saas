require "test_helper"

# Radar was one freelancer's tool before it was anyone's. Everything personal
# now comes from the profile and the career folder, and these tests keep it
# that way: any code path, prompt, view or config that names him, his clients
# or his projects fails here.
#
# Comments are allowed to. They record why the code is the way it is, and much
# of that history is his.
class NothingPersonalTest < ActiveSupport::TestCase
  PERSONAL = /farzam|pitchsmith|surge ?point|reviews on auto|padstats|curve.?tomorrow|lahore|karachi|pakistan|sohair/i

  SOURCES = %w[app config lib db/seeds.rb bin].flat_map { |dir|
    path = Rails.root.join(dir)
    path.file? ? [ path.to_s ] : Dir[path.join("**", "*")].select { |f| File.file?(f) }
  }.reject { |f| f.end_with?(".png", ".ico", ".svg", ".key", ".json") || f.include?("/assets/builds/") }

  def code_lines(file)
    File.readlines(file, chomp: true).each_with_index.reject { |line, _|
      stripped = line.strip
      stripped.start_with?("#", "//", "<%#", "*", "/*") || stripped.empty?
    }
  end

  test "no code, prompt, view or config names the original author or his work" do
    offenders = SOURCES.flat_map { |file|
      code_lines(file).filter_map { |line, i|
        "#{Pathname(file).relative_path_from(Rails.root)}:#{i + 1}: #{line.strip}" if line.match?(PERSONAL)
      }
    }
    # The country list in CountryName is data, not a personal fact.
    offenders.reject! { |o| o.start_with?("app/services/country_name.rb") }

    assert_empty offenders, "personal references in shipped code:\n#{offenders.join("\n")}"
  end

  test "someone else's prompts use their name" do
    Profile.current.update!(full_name: "Ada Lovelace", preferred_name: nil)
    posting = JobPosting.create!(upwork_id: "p-1", title: "Rails dev", description: "Build a Rails app", status: "matched")

    prompt = ProposalGenerator.new(posting).send(:prompt, ProposalArchetype.new(posting).call)
    assert_includes prompt, "Write a real Upwork proposal for Ada."
    assert_not_includes prompt, "Farzam"

    Lesson.create!(body: "Keep it short.")
    assert_includes Lesson.prompt_block, "WHAT ADA HAS CORRECTED BEFORE"
  end

  test "the self-introduction check follows the profile" do
    Profile.current.update!(full_name: "Ada Lovelace", preferred_name: nil)
    assert_match ProposalCheck.self_intro, "Hi, I'm Ada and I build Rails apps"
    assert_match ProposalCheck.self_intro, "I am Lovelace, a developer"
    assert_no_match ProposalCheck.self_intro, "Hi, I'm Farzam and I build Rails apps"
    assert_match ProposalCheck.self_intro, "With 9 years of experience in Rails"
  end

  test "location restrictions compare against the profile's country" do
    posting = JobPosting.new(preferred_locations: [ "Germany" ])
    Profile.current.update!(country: "Germany")
    assert_not posting.location_mismatch?

    Profile.current.update!(country: "India")
    assert posting.location_mismatch?

    # Upwork sometimes sends an alpha-3 code.
    Profile.current.update!(country: "United States")
    assert_not JobPosting.new(preferred_locations: [ "USA" ]).location_mismatch?
  end

  test "with no country on the profile nothing is refused for location" do
    Profile.current.update!(country: nil)
    assert_not JobPosting.new(preferred_locations: [ "Germany" ]).location_mismatch?
  end

  test "working-hour overlap is measured from the profile's timezone" do
    posting = JobPosting.new(client_timezone: "Europe/Berlin")
    Profile.current.update!(timezone: "Europe/Berlin")
    assert_equal 9, posting.client_overlap_hours
  end
end
