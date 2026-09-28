module Setup
  # Every wizard page shares the rail, the step header and the footer. After
  # setup is finished the same pages are how a step is revisited from
  # Settings, so they must work in both modes.
  class BaseController < ApplicationController
    skip_before_action :require_setup
    layout "setup"

    helper_method :revisiting?

    private

    def revisiting? = Onboarding.complete?

    def go_to(key, **flash)
      redirect_to setup_step_path(key), **flash
    end

    # Where to go once a step is done: the next unresolved step during setup,
    # back to Settings when revisiting.
    def advance_from(key, **flash)
      return redirect_to(settings_path, **flash) if revisiting?

      target = Onboarding.current || Onboarding.find(key)
      redirect_to setup_step_path(target.key), **flash
    end
  end
end
