class SettingsController < ApplicationController
  def show
    @profile = Profile.current
    @connected = Upwork::TokenStore.new.connected?
    @accepted = Knowledge::Project.accepted.count
    @drafted = Knowledge::Project.drafted.count
    @scan = Knowledge::Scan.current
  end

  def toggle_native_notifications
    on = Setting.toggle_native_notifications!
    redirect_back fallback_location: root_path,
                  notice: on ? "Mac notifications on, as well as browser alerts." :
                               "Mac notifications off. Browser alerts still work whenever a Radar tab is open."
  end

  def toggle_auto_polling
    on = Setting.toggle_auto_polling!
    redirect_back fallback_location: root_path,
                  notice: on ? "Watching Upwork again. The first check runs within a minute." :
                               "Automatic checks paused. Nothing new arrives until you resume, or press Check now."
  end

  def toggle_auto_generate
    on = Setting.toggle_auto_generate!
    redirect_back fallback_location: root_path,
                  notice: on ? "Writing automatically. Strong matches in automatic searches get a proposal straight away." :
                               "Automatic writing is off. Jobs still arrive and alert you; press Write one when you want a proposal."
  end
end
