class ApplicationController < ActionController::Base
  # Until setup is finished there is nothing the rest of the app can do: no
  # key, no profile, no searches. Every page leads back to the step they are on.
  before_action :require_setup

  # A dead scheduler leaves the workers alive, so any request reaching the app
  # can keep polling going. The open alerts tab hits /alerts every 30 seconds,
  # which makes this a real safety net rather than a theoretical one.
  before_action :revive_polling_if_stalled

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def require_setup
    return if Onboarding.complete?

    return render(json: { setup: setup_path }, status: :conflict) if request.format.json?

    redirect_to setup_path
  end

  def revive_polling_if_stalled
    PollHealth.revive! if Onboarding.complete?
  end
end
