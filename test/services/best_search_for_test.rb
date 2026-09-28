require "test_helper"

# "Full-Stack Engineer - Health Care" was re-homed to Web application because
# its SKILLS list said "Web Application". That both zeroed its title score and
# auto-wrote a proposal, even though Farzam had deliberately made the Full
# stack search notify-only.
class BestSearchForTest < ActiveSupport::TestCase
  setup do
    @web = SavedSearch.create!(name: "Web application", terms: [ "web application", "web developer" ],
                               threshold: 70, hot_threshold: 70, auto_generate: true, active: true, position: 1)
    @full = SavedSearch.create!(name: "Full stack", terms: [ "full stack engineer", "full stack developer" ],
                                threshold: 70, hot_threshold: 75, auto_generate: false, active: true, position: 2)
    @searches = [ @web, @full ]
  end

  def home(posting) = BestSearchFor.call(posting, fallback: @web, searches: @searches)

  test "the search named in the title wins over one matched only by skills" do
    posting = JobPosting.new(title: "Full-Stack Engineer - Health Care",
                             description: "B2B telehealth SaaS platform.",
                             skills: [ "Web Application", "PostgreSQL" ])
    assert_equal @full, home(posting), "the title says what the job is"
  end

  test "honouring the title keeps a notify-only job from auto-writing" do
    posting = JobPosting.new(title: "Full-Stack Engineer - Health Care", skills: [ "Web Application" ])
    assert_not home(posting).auto_generate?, "Full stack is notify-only on purpose"
  end

  test "with no title match, the lowest hot bar still wins" do
    posting = JobPosting.new(title: "Engineer wanted", description: "We need a web application built.")
    assert_equal @web, home(posting)
  end

  test "a title match beats a lower hot bar even when both match" do
    posting = JobPosting.new(title: "Full Stack Developer", description: "Build a web application.")
    assert_equal @full, home(posting)
  end

  test "nothing matching falls back" do
    assert_equal @web, home(JobPosting.new(title: "Interior decorator", description: "Curtains."))
  end
end
