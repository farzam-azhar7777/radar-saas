require "test_helper"

class SavedSearchesPageTest < ActionDispatch::IntegrationTest
  setup do
    @ai = SavedSearch.create!(name: "AI", terms: [ "ai agent" ], threshold: 70, hot_threshold: 80, auto_generate: true, active: true, position: 1)
    @rails = SavedSearch.create!(name: "Rails", terms: [ "ruby on rails" ], threshold: 70, hot_threshold: 85, auto_generate: false, active: true, position: 2)
    @mern = SavedSearch.create!(name: "MERN", terms: [ "mern" ], threshold: 70, hot_threshold: 82, auto_generate: false, active: false, position: 3)
  end

  test "every search can be switched and edited from the list" do
    get saved_searches_path

    assert_response :success
    assert_select "button[role=switch]", 6
    assert_select "input[name='ids[]'][form=bulk-form]", 3
    assert_select "#search_#{@rails.id}_saved_search_name[value=?]", "Rails"
  end

  test "a switch flips one setting on one search" do
    post toggle_saved_search_path(@rails, field: "auto_generate")
    assert @rails.reload.auto_generate?
    assert_redirected_to saved_searches_path

    post toggle_saved_search_path(@ai, field: "active")
    assert_not @ai.reload.active?
  end

  test "a switch only touches the two settings it is for" do
    post toggle_saved_search_path(@ai, field: "name")
    assert_response :unprocessable_entity
  end

  test "an inline edit saves one search and returns to the list" do
    patch saved_search_path(@rails), params: { saved_search: { name: "Rails", terms_text: "ruby on rails, hotwire",
                                                               threshold: 72, hot_threshold: 84 } }

    assert_redirected_to saved_searches_path
    assert_equal [ "ruby on rails", "hotwire" ], @rails.reload.terms_list
    assert_equal [ 72, 84 ], [ @rails.threshold, @rails.hot_threshold ]
  end

  test "bulk changes only what was chosen, only on the ticked searches" do
    post bulk_saved_searches_path, params: { ids: [ @rails.id, @mern.id ],
                                             bulk: { auto_generate: "on", active: "on", threshold: "", hot_threshold: "" } }

    assert_redirected_to saved_searches_path
    assert_equal "Updated 2 searches.", flash[:notice]
    assert [ @rails.reload, @mern.reload ].all? { |s| s.auto_generate? && s.active? }
    assert_equal [ 85, 82 ], [ @rails.hot_threshold, @mern.hot_threshold ], "left as is"
    assert_equal 80, @ai.reload.hot_threshold, "an unticked search is untouched"
  end

  test "bulk saves what is valid and names what is not" do
    post bulk_saved_searches_path, params: { ids: [ @ai.id, @rails.id ], bulk: { threshold: "84" } }

    assert_equal 84, @rails.reload.threshold
    assert_equal 70, @ai.reload.threshold
    assert_match "Updated 1 search. Not saved: AI", flash[:alert]
  end

  test "bulk needs a search and a change" do
    post bulk_saved_searches_path, params: { bulk: { active: "off" } }
    assert_equal "Tick at least one search.", flash[:alert]

    post bulk_saved_searches_path, params: { ids: [ @ai.id ], bulk: { active: "" } }
    assert_equal "Choose something to change.", flash[:alert]
  end
end
