class PassedOverAdviceController < ApplicationController
  def apply
    search = SavedSearch.find(params[:search_id])
    from = search.threshold
    moved = PassedOverAdvice.apply!(search, params[:to].to_i)
    redirect_to filtered_path, notice: "#{search.name}'s inbox line is now #{search.threshold} (was #{from}). " \
                                       "#{moved.zero? ? 'No recent passed-over job clears it yet.' : "#{moved} recent #{'job'.pluralize(moved)} that clear it moved to the inbox."}"
  end

  def dismiss
    PassedOverAdvice.dismiss!(params[:key])
    redirect_to filtered_path, notice: "Hidden. Radar suggests it again only if the numbers change."
  end
end
