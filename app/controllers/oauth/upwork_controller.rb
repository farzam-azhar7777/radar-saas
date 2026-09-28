module Oauth
  # Upwork redirects the browser here with ?code=... when the callback address
  # reaches this app (a tunnel, say). Exchanging it here means the flow
  # completes on its own. Setup also accepts the address pasted by hand, which
  # is the path that works with no tunnel at all.
  class UpworkController < ApplicationController
    skip_before_action :require_setup
    skip_forgery_protection only: :callback

    def connect
      redirect_to Upwork::Client.authorize_url, allow_other_host: true
    end

    def callback
      if params[:error].present?
        return redirect_to setup_step_path("upwork_connect"), alert: "Upwork declined: #{params[:error_description] || params[:error]}"
      end
      return redirect_to setup_step_path("upwork_connect"), alert: "Upwork sent no authorization code." if params[:code].blank?

      Upwork::Client.new.exchange_code(params[:code])
      result = UpworkProbe.call
      if result.ok?
        Onboarding.stamp!("upwork_connect")
        redirect_to Onboarding.complete? ? settings_path : setup_path, notice: "Upwork connected."
      else
        redirect_to setup_step_path("upwork_connect"), alert: result.error
      end
    rescue StandardError => e
      Rails.logger.error("[Upwork OAuth] #{e.class}: #{e.message}")
      redirect_to setup_step_path("upwork_connect"), alert: Upwork::TokenError.explain(e.message)
    end
  end
end
