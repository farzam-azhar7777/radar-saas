class JobSearchesController < ApplicationController
  def show
    @query = params[:q].to_s.strip
    @postings = @query.length >= 2 ? JobPosting.find_for_palette(@query) : []
    render layout: false
  end
end
