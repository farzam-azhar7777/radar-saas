require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "current is the fixture owner" do
    assert_equal "Farzam", Profile.first_name
  end

  test "with no profile at all a name is still available" do
    Profile.delete_all
    assert_equal "the freelancer", Profile.first_name
    assert_not Profile.current.complete?
  end

  test "first name falls back from preferred name to the first word of the full name" do
    assert_equal "Ada", Profile.new(full_name: "Ada Lovelace").first_name
    assert_equal "Countess", Profile.new(full_name: "Ada Lovelace", preferred_name: "Countess").first_name
  end

  test "the signature line keeps only the first clause of a long title" do
    p = Profile.new(full_name: "Ada Lovelace", title: "Full Stack Developer - Rails, React | AI")
    assert_equal "Full Stack Developer", p.short_title
    assert_equal "𝑨𝒅𝒂 𝑳𝒐𝒗𝒆𝒍𝒂𝒄𝒆\n𝑭𝒖𝒍𝒍 𝑺𝒕𝒂𝒄𝒌 𝑫𝒆𝒗𝒆𝒍𝒐𝒑𝒆𝒓", p.default_signature
  end

  test "their own signature wins over the generated one" do
    p = Profile.new(full_name: "Ada Lovelace", signature: "Ada")
    assert_equal "Ada", p.signature_text
  end

  test "setup requires name, title, country and a real timezone" do
    p = Profile.new(timezone: "Mars/Olympus")
    assert_not p.valid?(:setup)
    assert_includes p.errors[:timezone].join, "not a timezone"
    assert p.errors[:full_name].any?
    assert p.errors[:country].any?
  end

  test "a timezone reads the way people read one" do
    assert_match(/\AAsia\/Karachi \(UTC\+5\)\z/, profiles(:farzam).timezone_label)
  end

  test "Radar follows the profile's timezone" do
    assert_equal "Asia/Karachi", Radar.timezone
    profiles(:farzam).update!(timezone: "Europe/Berlin")
    assert_equal "Europe/Berlin", Radar.timezone
  end
end
