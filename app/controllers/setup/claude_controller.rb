module Setup
  class ClaudeController < BaseController
    RESULT = "setup.claude_check".freeze

    # Runs claude twice for real: once to prove it is signed in, once with the
    # model proposals are written with. Takes a few seconds, so the button
    # says so while it waits.
    def check
      result = ClaudeCheck.call
      Setting.set(RESULT, result.to_h.merge(at: Time.current.iso8601).to_json)

      if result.ok?
        Onboarding.stamp!("claude")
        advance_from("claude", notice: "Claude Code works. #{result.version}.")
      else
        Onboarding.unstamp!("claude")
        go_to("claude")
      end
    end

    def path
      value = params[:claude_path].to_s.strip
      value.present? ? Setting.set(Setting::CLAUDE_PATH, value) : Setting.clear(Setting::CLAUDE_PATH)
      go_to("claude", notice: value.present? ? "Radar will run #{value}. Check again." : "Radar will look for claude on the PATH. Check again.")
    end

    # For a plan that cannot use the pinned model: write with whatever the
    # claude command uses by default instead.
    def model
      if params[:model] == "default"
        Setting.set(Setting::WRITER_MODEL, "default")
      else
        Setting.clear(Setting::WRITER_MODEL)
      end
      go_to("claude", notice: "Saved. Check again to confirm.")
    end
  end
end
