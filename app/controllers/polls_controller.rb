class PollsController < ApplicationController
  def create
    PollAllSearchesJob.perform_later
    redirect_back fallback_location: root_path, notice: "Polling Upwork now."
  end
end
