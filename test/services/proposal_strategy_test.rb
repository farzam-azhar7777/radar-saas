require "test_helper"

class ProposalArchetypeTest < ActiveSupport::TestCase
  def posting(**over)
    JobPosting.new({ upwork_id: "x", title: "Rails developer",
                     description: "a" * 900, total_applicants: 20,
                     client_total_spent: 0, client_total_hires: 0 }.merge(over))
  end

  test "over eighty proposals is high competition" do
    assert_equal "C", ProposalArchetype.new(posting(total_applicants: 255)).key
  end

  test "a big spender with hires is the established shape" do
    a = ProposalArchetype.new(posting(client_total_spent: 99_000, client_total_hires: 40))
    assert_equal "B", a.key
    assert_equal 280..420, a.call[:words]
  end

  test "a thin description is treated as vague" do
    assert_equal "E", ProposalArchetype.new(posting(description: "Need a dev.")).key
  end

  test "a new client with few bids gets the consultative shape" do
    assert_equal "A", ProposalArchetype.new(posting(total_applicants: 3)).key
  end

  # Reversed on 2026-09-21. Shrinking the letter to 90-140 left the pitch a stub
  # under a wall of answers, which is backwards: the answers are read first, the
  # letter is what sells. The answers get capped instead.
  test "screening questions show in the label but no longer shorten the letter" do
    a = ProposalArchetype.new(posting(total_applicants: 3, screening_questions: [ "Why you?" ]))
    assert_equal "A+D", a.label
    assert_equal 320..460, a.call[:words]
    assert_equal 45..90, a.call[:answer_words]
  end

  test "signals name the competition and the client history" do
    signals = ProposalArchetype.new(posting(total_applicants: 12, client_total_spent: 4_000)).call[:signals]
    assert signals.any? { |s| s.include?("12 proposals") }
    assert signals.any? { |s| s.include?("$4000") }
  end
end

class ProposalCheckTest < ActiveSupport::TestCase
  SHAPE = { words: 280..420 }.freeze

  def check(body, posting: nil) = ProposalCheck.call(body, archetype: SHAPE, posting: posting)

  # Long enough to clear the archetype budgets, which were raised on 2026-09-23
  # because 140-to-260-word letters had no room to show depth.
  def good_body
    (%w[word] * 340).join(" ").prepend("Reviews on Auto Pilot is a Rails 8 SaaS where I wrote 842 of 863 commits. ")
  end

  def plain_body = (%w[word] * 340).join(" ")

  test "a clean proposal passes" do
    assert check(good_body)[:passed]
  end

  # The client wrote the post an hour ago. 34 of 111 proposals opened by
  # describing it back to them, and 2 of 47 sends were ever opened.
  test "an opener that restates the brief is rejected" do
    [ "You need a React developer who can move on both sides. ",
      "Your platform needs upgrading without downtime. ",
      "Building a tokenization platform means most work sits before Solidity. " ].each do |opener|
      result = check(opener + plain_body)
      assert_not result[:passed], opener
      assert result[:failures].any? { |f| f.include?("own job back") }, opener
    end
  end

  test "an opener with no question, number or project name is rejected" do
    assert check("The work here is interesting and I can help with it. " + plain_body)[:failures]
      .any? { |f| f.include?("no specific") }
  end

  # Reversed on 2026-09-23. Three drafts opening on a question were rejected in
  # a row: it reads as someone working the problem out rather than someone who
  # has shipped it.
  test "a question opener is rejected" do
    result = check("Quick question: are you locked into Supabase, or open to Postgres RLS? " + plain_body)
    assert_not result[:passed]
    assert result[:failures].any? { |f| f.include?("opens with a question") }
  end

  test "a wall of questions in the body is flagged" do
    body = "Reviews on Auto Pilot is a Rails 8 SaaS, 842 of 863 commits mine. " +
           "Where does the tenant boundary land? Per account? Per workspace? Who owns billing? " + plain_body
    assert check(body)[:notes].any? { |f| f.include?("questions") }
  end

  test "a named proof opener passes" do
    assert check("I took Bounce Rental from Rails 4.2 to 7.1 in production with Stripe live. " + plain_body)[:passed]
  end

  # The shape he actually sends, and the one the engine must produce.
  test "the opening he wrote himself passes" do
    opener = "Reviews on Auto Pilot at Surge Point is the closest thing to a CRM I have shipped recently: " \
             "a multi-tenant Rails 8 SaaS where I wrote 842 of 863 commits. Here is how I fit: "
    assert check(opener + plain_body)[:passed]
  end

  test "opening with a self introduction is rejected" do
    result = check("I'm Farzam, a developer with 9+ years of experience. " + good_body)
    assert_not result[:passed]
    assert result[:failures].any? { |f| f.include?("introduces Farzam") }
  end

  test "unicode bold in the preview is rejected because it burns the budget" do
    result = check("𝗬𝗼𝘂𝗿 checkout flow breaks first. " + good_body)
    assert_not result[:passed]
    assert result[:failures].any? { |f| f.include?("Unicode bold") }
  end

  test "bold after the preview window is fine" do
    body = good_body + " " + ("filler " * 20) + "𝗘𝘅𝗮𝗺𝗽𝗹𝗲𝘀"
    assert_empty check(body)[:failures].select { |f| f.include?("Unicode bold") }
  end

  test "em dashes are caught" do
    assert check("Your flow breaks — badly. " + good_body)[:failures].any? { |f| f.include?("dash") }
  end

  test "banned phrases are caught" do
    assert check("Your flow breaks. I would love to leverage my skills. " + good_body)[:failures].any? { |f| f.include?("banned") }
  end

  test "over-length is flagged with the budget quoted" do
    assert check((%w[word] * 600).join(" "))[:notes].any? { |f| f.include?("600 words, target 280-420") }
  end

  test "linking the Upwork profile is caught" do
    assert check(good_body + " https://www.upwork.com/freelancers/farzamazhar3")[:failures].any? { |f| f.include?("attaches it automatically") }
  end

  test "a planted opening word that is missing is caught, naming the word" do
    trap = JobPosting.new(description: "Please start your reply with the word banana so I know you read this.")
    assert check(good_body, posting: trap)[:failures].any? { |f| f.include?(%("banana")) }
    assert check("Banana. " + good_body, posting: trap)[:passed]
  end
end

class LessonScopeTest < ActiveSupport::TestCase
  setup do
    @search = SavedSearch.create!(name: "S#{SecureRandom.hex(3)}", terms: [ "rails" ])
    @global = Lesson.create!(body: "Never open with your name.")
    @shape  = Lesson.create!(body: "Keep high-competition proposals under 150 words.", archetype: "C")
    @scoped = Lesson.create!(body: "Mention Hotwire on Rails jobs.", saved_search: @search)
  end

  test "global rules apply everywhere" do
    assert_includes Lesson.for(saved_search: nil, archetype: "A"), @global
  end

  test "an archetype rule only applies to that shape" do
    assert_includes Lesson.for(archetype: "C"), @shape
    assert_not_includes Lesson.for(archetype: "A"), @shape
  end

  test "a search rule only applies to that search" do
    assert_includes Lesson.for(saved_search: @search), @scoped
    assert_not_includes Lesson.for(saved_search: nil), @scoped
  end

  test "an inactive rule is never injected" do
    @global.update!(active: false)
    assert_nil Lesson.prompt_block(archetype: "Z")
  end
end

class ProposalCheckLengthScopeTest < ActiveSupport::TestCase
  # A real C+D generation was reported as 376 words against a 90-140 budget
  # because the answers and the portfolio block were being counted as letter.
  SHAPE = { words: 280..420, has_questions: true }.freeze

  def body
    answers = "1. Describe your experience\n\n" + (%w[answer] * 200).join(" ")
    letter  = (%w[letter] * 120).join(" ")
    examples = "𝗘𝘅𝗮𝗺𝗽𝗹𝗲𝘀 𝗼𝗳 𝗠𝘆 𝗪𝗼𝗿𝗸\n\n" + (%w[project] * 80).join(" ")
    [ answers, "-----------------------------------------", letter, "-----------------------------------------", examples ].join("\n\n")
  end

  test "the budget is measured against the letter, not the answers" do
    result = ProposalCheck.call(body, archetype: { words: 100..200, has_questions: true })
    assert_equal 120, result[:letter_words]
    assert_operator result[:words], :>, 300, "the whole body really is long"
    assert_empty result[:failures].select { |f| f.include?("budget") }
  end

  test "the portfolio block never counts toward the letter" do
    no_questions = { words: 90..140, has_questions: false }
    letter = (%w[letter] * 120).join(" ")
    text = letter + "\n\n-----------------------------------------\n\n𝗘𝘅𝗮𝗺𝗽𝗹𝗲𝘀 𝗼𝗳 𝗠𝘆 𝗪𝗼𝗿𝗸\n\n" + (%w[p] * 300).join(" ")
    assert_equal 120, ProposalCheck.call(text, archetype: no_questions)[:letter_words]
  end

  test "a genuinely long letter is still reported" do
    long = { words: 90..140, has_questions: false }
    assert ProposalCheck.call((%w[w] * 400).join(" "), archetype: long)[:notes].any? { |f| f.include?("400 words") }
  end
end

class ProposalSeparatorTest < ActiveSupport::TestCase
  WITH_Q = { words: 90..140, has_questions: true }.freeze

  test "answers with no separator are rejected, because the budget cannot be measured" do
    body = "1. My experience\n\n" + (%w[w] * 300).join(" ")
    failures = ProposalCheck.call(body, archetype: WITH_Q)[:failures]
    assert failures.any? { |f| f.include?("not separated") }
  end

  test "a proposal without questions needs no separator" do
    body = (%w[w] * 120).join(" ")
    failures = ProposalCheck.call(body, archetype: { words: 90..140, has_questions: false })[:failures]
    assert_empty failures.select { |f| f.include?("not separated") }
  end
end

class LessonDashNormalisationTest < ActiveSupport::TestCase
  # Rules are injected into the prompt verbatim, so a dash in a rule teaches
  # the dash back into proposals.
  test "em and en dashes become hyphens" do
    l = Lesson.create!(body: "Cut the third answer — nobody reads that far.")
    assert_equal "Cut the third answer - nobody reads that far.", l.body
  end

  test "hyphenated words are left alone" do
    l = Lesson.create!(body: "On high-competition posts, keep it short — really short.")
    assert_includes l.body, "high-competition"
    assert_equal 0, l.body.count("—–")
  end
end

class AppliedWinRateTest < ActionDispatch::IntegrationTest
  # Four regenerations of one proposal is still one application.
  test "the shape table counts applications, not proposal versions" do
    search = SavedSearch.create!(name: "S#{SecureRandom.hex(3)}", terms: [ "rails" ])
    posting = JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails dev",
                                 status: "applied", applied_at: Time.current,
                                 outcome: "replied", saved_search: search, score: 80)
    4.times { |i| posting.proposals.create!(version: i + 1, body: "draft #{i}", archetype: "C+D") }

    get applied_path
    assert_response :success
    assert_select "body", /1 replied/
    assert_select "body", { text: /2 replied/, count: 0 }
  end
end

class AlertFeedTest < ActionDispatch::IntegrationTest
  # A new hot job scoring below the standing top ten was never announced,
  # because the feed was ranked by score and truncated.
  test "a newly arrived low-scoring hot job still reaches the feed" do
    search = SavedSearch.create!(name: "S#{SecureRandom.hex(3)}", terms: [ "rails" ],
                                 threshold: 70, hot_threshold: 70)
    15.times do |i|
      JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Older #{i}", status: "matched",
                         score: 95, saved_search: search, created_at: 2.days.ago, published_at: 2.days.ago)
    end
    newcomer = JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Just landed", status: "matched",
                                  score: 71, saved_search: search, created_at: Time.current, published_at: Time.current)

    get alerts_path
    ids = JSON.parse(response.body)["hot"].map { |h| h["id"] }
    assert_includes ids, newcomer.id, "the newest hot job must be in the feed"
    assert_equal newcomer.id, ids.first, "and it should lead, because the feed announces what is new"
  end
end
