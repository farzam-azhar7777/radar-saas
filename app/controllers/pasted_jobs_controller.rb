class PastedJobsController < ApplicationController
  def index
    @postings = JobPosting.pasted.includes(:proposals, :saved_search)
  end

  def new
    @pasted = PastedJob.new
  end

  def create
    @pasted = PastedJob.new(pasted_params)
    return render(:new, status: :unprocessable_entity) unless @pasted.save

    posting = @pasted.posting
    if posting.proposal_ready? || posting.generating?
      redirect_to posting, notice: "Radar already had this job, with its proposal. Opened it."
    else
      posting.queue_generation!
      redirect_to posting, notice: @pasted.already_in_radar? ? "Radar already had this job. Writing its proposal now." : "Writing the proposal now."
    end
  end

  private

  def pasted_params
    params.require(:pasted_job).permit(:post, :title, :questions, :budget, :budget_min, :budget_max, :bids, :link, :saved_search_id)
  end
end
