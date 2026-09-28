require "test_helper"

# Rewriting one part must leave every other part byte-for-byte alone. That is
# the entire promise of the feature, and the only way to be sure is to compare
# the other parts before and after.
class SectionRewriteTest < ActionDispatch::IntegrationTest
  setup do
    @posting = JobPosting.create!(
      upwork_id: "part-#{SecureRandom.hex(4)}", title: "Rails backend for a CRM",
      description: "Build APIs and integrations for a new CRM platform." * 8,
      status: "matched", score: 82, published_at: 2.hours.ago
    )
    @proposal = @posting.proposals.create!(
      version: 1, archetype: "A", generated_at: Time.current,
      body: "PadStats is a Rails 7 GraphQL API.\n\nI would own the billing surface.",
      checks: { "passed" => true }
    )
    @proposal.ensure_sections!
  end

  def opening = @proposal.sections.first

  test "the page offers a rewrite for every part, named as the writer named it" do
    get job_posting_path(@posting)

    assert_response :success
    @proposal.sections.each do |part|
      assert_select "##{ActionView::RecordIdentifier.dom_id(part)}"
      assert_select "form[action=?]", rewrite_proposal_section_path(part)
    end
  end

  test "rewriting one part queues only that part and says so" do
    assert_enqueued_with(job: RewriteSectionJob) do
      post rewrite_proposal_section_path(opening), params: { feedback: "Lead with the commit count." }
    end

    assert_redirected_to job_posting_path(@posting)
    assert_match(/Opening/, flash[:notice])
    assert opening.reload.rewriting?
    assert_equal "Lead with the commit count.", opening.rewrite_feedback
  end

  test "an empty note changes nothing and costs nothing" do
    assert_no_enqueued_jobs(only: RewriteSectionJob) do
      post rewrite_proposal_section_path(opening), params: { feedback: "   " }
    end

    assert_not opening.reload.rewriting?
    assert flash[:alert].present?
  end

  test "a second rewrite is refused while one is in flight" do
    opening.update!(rewrite_queued_at: Time.current)

    assert_no_enqueued_jobs(only: RewriteSectionJob) do
      post rewrite_proposal_section_path(@proposal.sections.last), params: { feedback: "Shorter." }
    end
    assert_match(/already being written/, flash[:alert])
  end

  test "remember also teaches a rule, once only records this part" do
    assert_difference "Feedback.count", 1 do
      assert_enqueued_with(job: DistillLessonJob) do
        post rewrite_proposal_section_path(opening), params: { feedback: "No bold.", scope: "remember" }
      end
    end
    assert Feedback.order(:id).last.remembered

    assert_no_difference "Feedback.count" do
      assert_no_enqueued_jobs(only: DistillLessonJob) do
        post rewrite_proposal_section_path(@proposal.sections.last), params: { feedback: "Shorter." }
      end
    end
  end

  # --- what the job actually does -----------------------------------------

  test "the job swaps one part, copies the rest, and re-checks the whole" do
    target = opening
    untouched = @proposal.sections.reject { |s| s.id == target.id }.map(&:body)

    with_stubbed_rewriter("PandOS is a Rails 8.1 multi-tenant platform.") do
      RewriteSectionJob.new.perform(target, feedback: "Use PandOS.")
    end

    fresh = @posting.proposals.reload.order(version: :desc).first
    assert_equal 2, fresh.version
    assert_equal "PandOS is a Rails 8.1 multi-tenant platform.", fresh.sections.first.body
    assert_equal untouched, fresh.sections.drop(1).map(&:body), "every other part must survive untouched"
    assert_equal fresh.assembled, fresh.body, "body and parts must not drift"
    assert fresh.checks.present?, "the whole proposal is re-checked, not just the part"
    assert_equal "Opening", fresh.rewritten_section_label
    assert_not target.reload.rewriting?
  end

  test "the earlier version is kept, so a bad rewrite is recoverable" do
    before = @proposal.body

    with_stubbed_rewriter("Something worse.") do
      RewriteSectionJob.new.perform(opening, feedback: "Change it.")
    end

    assert_equal before, @proposal.reload.body
    assert_equal 2, @posting.proposals.count
  end

  test "a failed rewrite clears the spinner and says what happened" do
    original = SectionRewriter.method(:call)
    SectionRewriter.define_singleton_method(:call) { |*, **| raise SectionRewriter::RewriteError, "claude exited 1" }

    RewriteSectionJob.new.perform(opening, feedback: "Change it.")

    assert_not opening.reload.rewriting?
    assert_equal 1, @posting.proposals.count, "a failure must not leave a half-written version"
    assert_match(/claude exited 1/, @posting.reload.generation_error)
  ensure
    SectionRewriter.define_singleton_method(:call, original)
  end

  test "deriving parts twice does not double them" do
    2.times { @proposal.ensure_sections! }

    assert_equal 2, ProposalSection.where(proposal_id: @proposal.id).count
  end

  # Found by running it: a rewritten answer pasted his Upwork profile URL in,
  # which fails the whole proposal on a rule the part itself never saw.
  test "the prompt carries the rules a part can break on its own" do
    rules = SectionRewriter.new(opening, feedback: "Shorter.").send(:rules)

    assert_match(/Never link their Upwork profile/, rules)
    assert_match(/em or en dashes/, rules)
    ProposalCheck::BANNED.first(3).each { |w| assert_includes rules, w }
  end

  test "the prompt stays small, because that is the point" do
    text = SectionRewriter.new(opening, feedback: "Shorter.").send(:prompt)

    assert_operator text.length, :<, 8_000, "a part rewrite that sends everything costs more than a full write"
    assert_includes text, "PadStats is a Rails 7 GraphQL API.", "the part being rewritten is sent in full"
  end

  private

  # Never let a test shell out to claude -p: it costs real money and minutes.
  def with_stubbed_rewriter(body)
    original = SectionRewriter.method(:call)
    result = SectionRewriter::Result.new(body: body, duration_ms: 900, meta: { "total_cost_usd" => 0.02 })
    SectionRewriter.define_singleton_method(:call) { |*, **| result }
    yield
  ensure
    SectionRewriter.define_singleton_method(:call, original)
  end
end
