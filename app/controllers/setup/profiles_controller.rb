module Setup
  class ProfilesController < BaseController
    FIELDS = %i[full_name preferred_name title email country city timezone hourly_rate hours_per_week
                response_time availability years_experience languages skills upwork_url github_url github_note
                linkedin_url website_url portfolio_url credentials_line summary].freeze

    def update
      @profile = Profile.current
      @profile.assign_attributes(params.require(:profile).permit(*FIELDS).transform_values { |v| v.is_a?(String) ? v.strip.presence : v })

      if @profile.save(context: :setup)
        CareerFolder.write_profile!(@profile)
        # The generator is told to read writing-voice.md, so it exists from
        # here on, with plain guidance until the voice step fills it.
        CareerFolder.write_voice!(@profile)
        Knowledge::Publisher.call
        advance_from("profile", notice: "Saved. Every proposal now signs as #{@profile.first_name}.")
      else
        @step = Onboarding.find("profile")
        flash.now[:alert] = "Fix the highlighted #{'field'.pluralize(@profile.errors.attribute_names.size)} to continue."
        render "setup/steps/show", status: :unprocessable_entity
      end
    end
  end
end
