require "test_helper"

class TextMatchTest < ActiveSupport::TestCase
  def title(text) = TextMatch.normalize(text)

  # The healthcare job that was filtered: the search term is the phrase
  # "full stack developer" and the title split it with "Healthcare".
  test "a phrase split by another word still matches the title" do
    t = title("Senior Full Stack Healthcare Developer - Technical Lead")
    assert_not TextMatch.includes?(t, "full stack developer"), "contiguous matching cannot see it"
    assert TextMatch.spans?(t, "full stack developer")
  end

  test "word order is required, so unrelated titles do not match" do
    t = title("Full time developer needed to stack shelves")
    assert_not TextMatch.spans?(t, "full stack developer")
  end

  test "a missing word means no match" do
    t = title("Senior Healthcare Developer")
    assert_not TextMatch.spans?(t, "full stack developer")
  end

  test "whole words only, so ror does not match error" do
    assert_not TextMatch.spans?(title("Fix an error in checkout"), "ror")
    assert TextMatch.spans?(title("RoR engineer"), "ror")
  end

  # Unbounded gaps matched "ai engineer" inside "AI-Native Software &
  # Infrastructure Engineer", which put an infrastructure job on the Rails
  # auto-write search.
  test "a gap of more than two words is not the same phrase" do
    assert_not TextMatch.spans?(title("AI-Native Software & Infrastructure Engineer"), "ai engineer")
    assert_not TextMatch.spans?(title("Python/C++ Engineer | Flask, Microservice, API, NumPy"), "python api")
  end

  test "one or two dropped-in words is still the same phrase" do
    assert TextMatch.spans?(title("Senior Full Stack Healthcare Developer"), "full stack developer")
    assert TextMatch.spans?(title("Senior Full Stack Web Application Developer"), "full stack developer")
  end

  test "an exact phrase still matches" do
    assert TextMatch.spans?(title("Full Stack Developer wanted"), "full stack developer")
  end
end
