# Asks Claude for search suggestions in the background; the searches step
# refreshes itself when they land.
class SuggestSearchesJob < ApplicationJob
  queue_as :knowledge

  def perform
    SearchSuggester.call
    Turbo::StreamsChannel.broadcast_refresh_to("setup")
  rescue StandardError => e
    Rails.logger.warn("[SuggestSearchesJob] #{e.message}")
  end
end
