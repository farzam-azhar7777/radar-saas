# A posting is pulled by whichever search ran first, but that is an accident of
# iteration order, not a judgement about the job. "Ruby on Rails Developer for
# Web Application" can be caught by the broad "Full stack / web dev" search and
# then be held to that search's deliberately strict hot bar.
#
# So after a posting is pulled, re-home it: among every active search whose
# terms actually match, keep the one most willing to call it hot. Specific
# searches beat generic ones, which is the behaviour Farzam expects.
class BestSearchFor
  def self.call(...) = new(...).call

  def initialize(posting, fallback:, searches: SavedSearch.active.to_a)
    @posting = posting
    @fallback = fallback
    @searches = searches
  end

  def call
    candidates = @searches.select { |s| matches?(s) }
    return @fallback if candidates.empty?

    # A title match outranks everything. The title is what the job IS; the
    # description and skills are context it happens to mention. Without this,
    # "Full-Stack Engineer - Health Care" was re-homed to Web application
    # because its skills list contained "Web Application", which both zeroed
    # its title score and, because Web application auto-writes while Full stack
    # deliberately does not, spent money Farzam had chosen not to spend.
    #
    # Then lowest hot_threshold, then the more specific search (fewer terms).
    candidates.min_by { |s| [ titled?(s) ? 0 : 1, s.hot_threshold.to_i, s.terms_list.size ] }
  end

  private

  def haystack
    @haystack ||= TextMatch.haystack_for(@posting)
  end

  def title
    @title ||= TextMatch.title_of(@posting)
  end

  def titled?(search)
    search.terms_list.any? { |t| TextMatch.includes?(title, t) || (t.include?(" ") && TextMatch.spans?(title, t)) }
  end

  def matches?(search)
    return false if search.excluded_keywords_list.any? { |kw| TextMatch.includes?(haystack, kw) }

    search.terms_list.any? { |t| TextMatch.includes?(haystack, t) }
  end
end
