require "test_helper"

# On 2026-09-09 and 09-10 four generations failed, two of them because the
# claude CLI had lost its Keychain credentials after a sleep/wake cycle. Radar
# said nothing. Farzam found them by noticing "Failed" while scrolling.
class GenerationHealthTest < ActiveSupport::TestCase
  def failed(error:, at: Time.current)
    p = JobPosting.create!(upwork_id: SecureRandom.hex(6), title: "Rails dev",
                           status: "generation_failed", score: 80, generation_error: error)
    p.update_columns(updated_at: at)
    p
  end

  test "a healthy writer reports ok" do
    assert_equal :ok, GenerationHealth.status
    assert_not GenerationHealth.blocked?
  end

  test "one failure is degraded, not blocked" do
    failed(error: "claude exited 1: API Error: Overloaded")
    assert_equal :degraded, GenerationHealth.status
    assert_not GenerationHealth.blocked?, "one bad run is not a broken writer"
  end

  test "repeated login failures with no successes means the writer is blocked" do
    2.times { failed(error: 'claude exited 1: {"result":"Not logged in · Please run /login"}') }
    assert GenerationHealth.blocked?
    assert_equal :blocked, GenerationHealth.status
    assert_match "re-authenticate", GenerationHealth.message
  end

  test "a login failure alongside working generations is not blocked" do
    2.times { failed(error: "Not logged in · Please run /login") }
    JobPosting.first.proposals.create!(version: 1, body: "written fine", generated_at: Time.current)
    assert_not GenerationHealth.blocked?, "something is writing, so the writer is not down"
  end

  test "transient errors never read as blocked, however many" do
    3.times { failed(error: "claude exited 1: API Error: Overloaded") }
    assert_not GenerationHealth.blocked?
    assert_equal :degraded, GenerationHealth.status
  end

  test "old failures fall out of the window" do
    2.times { failed(error: "Not logged in · Please run /login", at: 3.hours.ago) }
    assert_equal :ok, GenerationHealth.status
  end

  test "a successful rewrite clears the recorded error" do
    p = failed(error: "Not logged in")
    p.update!(status: "matched", generation_error: nil)
    assert_nil p.reload.generation_error
    assert_equal :ok, GenerationHealth.status
  end
end
