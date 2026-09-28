require "test_helper"

class OnboardingTest < ActiveSupport::TestCase
  setup do
    Setting.clear(Onboarding::COMPLETED_AT)
    Profile.delete_all
    SavedSearch.delete_all
  end

  test "ten steps; exactly three can be skipped, and each says what skipping costs" do
    assert_equal 10, Onboarding.steps.size
    assert_equal %w[knowledge voice preferences], Onboarding.steps.select(&:skippable?).map(&:key)
    Onboarding.steps.select(&:skippable?).each { |s| assert s.skip_cost.present?, s.key }
    Onboarding.steps.each { |s| assert s.why.present?, s.key }
  end

  test "a required step refuses to be skipped" do
    assert_raises(ArgumentError) { Onboarding.skip!("searches") }
  end

  test "the current step is the first one neither done nor skipped, and later ones are out of reach" do
    assert_equal "welcome", Onboarding.current.key
    Onboarding.stamp!("welcome")
    assert_equal "claude", Onboarding.current.key
    assert Onboarding.reachable?("welcome")
    assert_not Onboarding.reachable?("profile")
  end

  test "a skipped step that is later done counts as done" do
    Onboarding.skip!("voice")
    assert Onboarding.skipped?("voice")
    Profile.create!(full_name: "Ada", voice_samples: [ "hello" ])
    assert Onboarding.done?("voice")
    assert_not Onboarding.skipped?("voice")
  end

  test "progress counts resolved steps" do
    assert_equal 0, Onboarding.progress
    Onboarding.stamp!("welcome")
    Onboarding.skip!("voice")
    assert_equal 20, Onboarding.progress
  end

  test "once complete, every step can be revisited" do
    Onboarding.complete!
    assert Onboarding.steps.all? { |s| Onboarding.reachable?(s.key) }
  end
end
