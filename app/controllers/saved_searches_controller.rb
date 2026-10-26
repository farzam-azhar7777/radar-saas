class SavedSearchesController < ApplicationController
  TOGGLES = { "auto_generate" => [ "Writes automatically", "Alerts only" ], "active" => [ "Active", "Paused" ] }.freeze

  before_action :set_search, only: %i[edit update destroy toggle]

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

  def toggle
    field = params[:field].to_s
    return head(:unprocessable_entity) unless TOGGLES.key?(field)

    @search.update!(field => !@search.public_send(field))
    on, off = TOGGLES.fetch(field)
    redirect_to saved_searches_path, notice: "#{@search.name}: #{@search.public_send(field) ? on : off}."
  end

  def bulk
    searches = SavedSearch.where(id: Array(params[:ids])).ordered.to_a
    return redirect_to(saved_searches_path, alert: "Tick at least one search.") if searches.empty?

    changes = bulk_changes
    return redirect_to(saved_searches_path, alert: "Choose something to change.") if changes.empty?

    failed = searches.reject { |s| s.update(changes) }
    saved = searches.size - failed.size
    notice = "Updated #{pluralize(saved, 'search')}."
    return redirect_to(saved_searches_path, notice: notice) if failed.empty?

    redirect_to saved_searches_path, alert: "#{notice} Not saved: " +
      failed.map { |s| "#{s.name} (#{s.errors.full_messages.to_sentence.downcase})" }.join("; ") + "."
  end

  def destroy
    @search.destroy
    redirect_to saved_searches_path, notice: "Search deleted."
  end

  private

  def set_search
    @search = SavedSearch.find(params[:id])
  end

  def bulk_changes
    given = params.fetch(:bulk, {}).permit(:auto_generate, :active, :threshold, :hot_threshold)
    switch = { "on" => true, "off" => false }
    {
      "auto_generate" => switch[given[:auto_generate]],
      "active" => switch[given[:active]],
      "threshold" => given[:threshold].presence&.to_i,
      "hot_threshold" => given[:hot_threshold].presence&.to_i
    }.compact
  end

  def pluralize(count, word) = ActionController::Base.helpers.pluralize(count, word)

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
