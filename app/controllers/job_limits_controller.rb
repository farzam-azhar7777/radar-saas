class JobLimitsController < ApplicationController
  def update
    @limits = JobLimits.new(params[:limits])
    return redirect_to(saved_searches_path, notice: limits_notice) if @limits.save

    @searches = SavedSearch.ordered
    @impact = @limits.impact(JobLimits.recent_matches)
    flash.now[:alert] = "Limits not saved: #{@limits.errors.to_sentence}."
    render "saved_searches/index", status: :unprocessable_entity
  end

  def preview
    limits = JobLimits.new(params[:limits])
    render partial: "job_limits/impact", locals: { limits: limits, impact: limits.impact(JobLimits.recent_matches), preview: true }
  end

  private

  def limits_notice
    @limits.any? ? "Limits saved. They apply to every search, from the next job that arrives." : "Limits cleared."
  end
end
