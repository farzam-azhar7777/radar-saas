class SavedSearchesController < ApplicationController
  before_action :set_search, only: %i[edit update destroy]

  def index
    @searches = SavedSearch.ordered
  end

  def new
    @search = SavedSearch.new(threshold: 70, hot_threshold: 80, active: true, position: (SavedSearch.maximum(:position) || 0) + 1)
  end

  def create
    @search = SavedSearch.new(search_params)
    return redirect_to saved_searches_path, notice: "Search created." if @search.save

    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    return redirect_to saved_searches_path, notice: "Search updated." if @search.update(search_params)

    render :edit, status: :unprocessable_entity
  end

  def destroy
    @search.destroy
    redirect_to saved_searches_path, notice: "Search deleted."
  end

  private

  def set_search
    @search = SavedSearch.find(params[:id])
  end

  def search_params
    permitted = params.require(:saved_search)
                      .permit(:name, :template_name, :threshold, :hot_threshold, :auto_generate, :position, :min_hourly, :min_fixed,
                              :active, :terms_text, :excluded_keywords_text)
    permitted[:terms] = split_list(permitted.delete(:terms_text))
    permitted[:excluded_keywords] = split_list(permitted.delete(:excluded_keywords_text))
    permitted
  end

  def split_list(value)
    value.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
