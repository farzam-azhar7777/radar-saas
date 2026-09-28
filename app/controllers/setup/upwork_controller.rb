module Setup
  class UpworkController < BaseController
    VERIFIED = "setup.upwork_probe".freeze

    def key
      attrs = params.require(:upwork).permit(:client_id, :client_secret, :redirect_uri, :tenant_id).to_h.symbolize_keys
      # A secret field left blank means "keep the one saved", because the page
      # never shows it back.
      attrs.delete(:client_secret) if attrs[:client_secret].blank? && Credential.get("upwork.client_secret").present?

      errors = []
      errors << "the Client ID" if attrs[:client_id].blank?
      errors << "the Client Secret" if attrs[:client_secret].blank? && Credential.get("upwork.client_secret").blank?
      errors << "the Callback URL" if attrs[:redirect_uri].blank?
      if errors.any?
        return go_to("upwork_key", alert: "Add #{errors.to_sentence} to continue.")
      end
      unless attrs[:redirect_uri].to_s.start_with?("https://")
        return go_to("upwork_key", alert: "The Callback URL must start with https://, exactly as it is entered on Upwork.")
      end

      changed = Credential.get("upwork.client_id") != attrs[:client_id].strip
      Credential.set_upwork(attrs)
      # A different key cannot use the old key's sign-in.
      if changed
        Upwork::TokenStore.new.clear!
        Onboarding.unstamp!("upwork_connect")
      end
      advance_from("upwork_key", notice: "Key saved and encrypted on this computer.")
    end

    def authorize
      return go_to("upwork_key", alert: "Add your Upwork API key first.") unless Upwork::Client.configured?

      redirect_to Upwork::Client.authorize_url, allow_other_host: true
    end

    # The address Upwork sent them to, pasted back. The page it pointed at
    # did not need to load.
    def code
      code = Upwork::Client.code_from(params[:callback])
      return go_to("upwork_connect", alert: "That does not contain a code. Paste the whole address from the tab Upwork sent you to.") if code.nil?

      Upwork::Client.new.exchange_code(code)
      verify
    rescue Upwork::Error => e
      go_to("upwork_connect", alert: Upwork::TokenError.explain(e.message))
    end

    def verify
      result = UpworkProbe.call
      Setting.set(VERIFIED, result.to_h.merge(at: Time.current.iso8601).to_json)

      if result.ok?
        Onboarding.stamp!("upwork_connect")
        advance_from("upwork_connect", notice: "Connected. Upwork has #{result.total || 'plenty of'} open jobs matching \"developer\" right now.")
      else
        Onboarding.unstamp!("upwork_connect")
        go_to("upwork_connect", alert: result.error)
      end
    end

    def disconnect
      Upwork::TokenStore.new.clear!
      Onboarding.unstamp!("upwork_connect")
      go_to("upwork_connect", notice: "Disconnected. Connect again to keep finding jobs.")
    end
  end
end
