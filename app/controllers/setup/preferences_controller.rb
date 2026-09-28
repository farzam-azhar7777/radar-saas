module Setup
  class PreferencesController < BaseController
    def update
      prefs = params.require(:preferences).permit(:auto_generate, :daily_cap, :active_from, :active_to, :native_notifications)

      Setting.set(Setting::AUTO_GENERATE, prefs[:auto_generate] == "1" ? "on" : "off")
      Setting.set(Setting::NATIVE_NOTIFICATIONS, prefs[:native_notifications] == "1" ? "on" : "off")
      Setting.set(Setting::DAILY_CAP, prefs[:daily_cap].to_i.clamp(1, 60)) if prefs[:daily_cap].present?
      from = prefs[:active_from].to_i.clamp(0, 23)
      to = prefs[:active_to].to_i.clamp(0, 23)
      Setting.set(Setting::ACTIVE_FROM, from)
      Setting.set(Setting::ACTIVE_TO, to <= from ? to + 24 : to)

      Onboarding.stamp!("preferences")
      Onboarding.unskip!("preferences")
      advance_from("preferences", notice: "Saved.")
    end
  end
end
