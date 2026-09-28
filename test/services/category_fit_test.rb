require "test_helper"

class CategoryFitTest < ActiveSupport::TestCase
  def fit(**attrs) = CategoryFit.call(JobPosting.new(**attrs)).first

  test "web development is a full match" do
    assert_equal 1.0, fit(category: "web_mobile_software_dev", subcategory: "web_development")
  end

  # The job that prompted this: a healthcare post naming no framework, which
  # Upwork had already filed under web development.
  test "the subcategory carries a post that names no stack" do
    posting = JobPosting.new(title: "Senior Full Stack Healthcare Developer",
                             description: "PointClickCare, X12 EDI 837/835, ICD-10.",
                             category: "web_mobile_software_dev", subcategory: "web_development")
    fraction, note = CategoryFit.call(posting)
    assert_equal 1.0, fraction
    assert_match "web development", note
  end

  test "ecommerce scores low, because Upwork files Shopify work there" do
    assert_operator fit(category: "web_mobile_software_dev", subcategory: "ecommerce_development"), :<=, 0.2
  end

  test "design and marketing are not his field" do
    assert_equal 0.0, fit(category: "design_creative", subcategory: "web_mobile_design")
    assert_equal 0.0, fit(category: "sales_marketing", subcategory: "digital_marketing")
  end

  test "an unknown subcategory falls back to the category" do
    assert_equal 0.6, fit(category: "web_mobile_software_dev", subcategory: "something_upwork_added_later")
  end

  test "missing classification is neutral, not punitive" do
    assert_equal 0.5, fit(category: nil, subcategory: nil)
  end

  test "an unrecognised category scores zero rather than guessing" do
    assert_equal 0.0, fit(category: "legal", subcategory: "public_law")
  end

  test "the weights still total 100" do
    assert_equal 100, SavedSearch::DEFAULT_WEIGHTS.values.sum
  end

  test "category_fit is actually applied to a score" do
    search = SavedSearch.create!(name: "W", terms: [ "web application" ], threshold: 70, hot_threshold: 80)
    base = { upwork_id: SecureRandom.hex(6), title: "Web application developer", status: "matched" }
    web = ScoreJobPosting.call(JobPosting.new(**base, category: "web_mobile_software_dev", subcategory: "web_development"), saved_search: search).score
    legal = ScoreJobPosting.call(JobPosting.new(**base, category: "legal", subcategory: "public_law"), saved_search: search).score
    assert_equal 10, web - legal, "the full weight of category_fit must separate them"
  end
end
