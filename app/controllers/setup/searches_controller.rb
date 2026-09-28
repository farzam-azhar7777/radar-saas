module Setup
  class SearchesController < BaseController
    PERMITTED = %i[name terms_text excluded_keywords_text threshold hot_threshold auto_generate template_name min_hourly].freeze

    def suggest
      SearchSuggester.start!
      go_to("searches", notice: "Radar is reading your work to suggest searches. About a minute.")
    end

    def create
      search = SavedSearch.new(search_attributes)
      if search.save
        Onboarding.unskip!("searches")
        go_to("searches", notice: "Watching for #{search.name}.")
      else
        go_to("searches", alert: "#{search.name.presence || 'That search'} was not added: #{search.errors.full_messages.to_sentence}.")
      end
    end

    def destroy
      search = SavedSearch.find(params[:id])
      search.destroy
      go_to("searches", notice: "Stopped watching for #{search.name}.")
    end

    # Rendered into the card's frame: what these words would bring in today.
    def preview
      @frame = params[:frame].presence || "preview"
      search = SavedSearch.new(search_attributes)
      @result = Upwork::Client.configured? && Upwork::TokenStore.new.connected? ? SearchPreview.call(search) : nil
      @search = search
      render partial: "setup/searches/preview", locals: { frame: @frame, result: @result, search: @search }
    end

    private

    def search_attributes
      attrs = params.require(:search).permit(*PERMITTED)
      {
        name: attrs[:name].to_s.strip,
        terms: split(attrs[:terms_text]),
        excluded_keywords: split(attrs[:excluded_keywords_text]).map(&:downcase),
        excluded_countries: [],
        threshold: attrs[:threshold].presence || 70,
        hot_threshold: attrs[:hot_threshold].presence || 80,
        auto_generate: attrs[:auto_generate] == "1",
        template_name: attrs[:template_name].presence,
        min_hourly: attrs[:min_hourly].presence || Profile.current.hourly_rate,
        active: true,
        position: (SavedSearch.maximum(:position) || 0) + 1
      }
    end

    def split(value) = value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
  end
end
