module Setup
  class VoicesController < BaseController
    def update
      profile = Profile.current
      voice = params.require(:voice).permit(:winning_opening, :winning_opening_context, :signature, samples: [])
      profile.update!(
        winning_opening: voice[:winning_opening].to_s.strip.presence,
        winning_opening_context: voice[:winning_opening_context].to_s.strip.presence,
        signature: voice[:signature].to_s.strip.presence,
        voice_samples: Array(voice[:samples]).map(&:strip).reject(&:blank?)
      )
      CareerFolder.write_voice!(profile)

      if Onboarding.done?("voice")
        Onboarding.unskip!("voice")
        advance_from("voice", notice: "Saved. Proposals will follow how you write.")
      elsif revisiting?
        redirect_to settings_path, notice: "Saved."
      else
        go_to("voice", alert: "Add at least one sample or your best opening, or skip this step.")
      end
    end
  end
end
