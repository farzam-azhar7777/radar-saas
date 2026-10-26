class AlertActionsController < ApplicationController
  ACTIONS = %w[write dismiss].freeze

  skip_forgery_protection
  before_action :verify_token

  def self.token_for(posting, action)
    verifier.generate({ "id" => posting.id, "do" => action }, expires_in: 3.days)
  end

  def self.verifier = Rails.application.message_verifier("alert-actions")

  def write
    if @posting.generating? || @posting.proposal_ready?
      render json: { ok: true, message: "Already written or being written." }
    else
      @posting.queue_generation!
      render json: { ok: true, message: "Writing the proposal now." }
    end
  end

  def dismiss
    @posting.update!(status: "dismissed")
    render json: { ok: true, message: "Dismissed." }
  end

  private

  def verify_token
    claims = self.class.verifier.verified(params[:token].to_s)
    return head(:forbidden) unless claims.is_a?(Hash) && ACTIONS.include?(action_name) &&
                                   claims["do"] == action_name && claims["id"].to_s == params[:id].to_s

    @posting = JobPosting.find(claims["id"])
  end
end
