module Upwork
  # What Upwork's OAuth errors mean for the person reading them. Upwork answers
  # with terse JSON; each case has a different fix, and "try again" is the
  # wrong advice for most of them.
  module TokenError
    module_function

    def explain(message)
      text = description(message)
      case text
      when /client_id/i
        "Upwork does not recognise this Key (Client ID). Check it in the Upwork API key step, character for character."
      when /client_secret|invalid_client|client authentication/i
        "Upwork rejected the Secret for this key. Paste it again in the Upwork API key step."
      when /redirect/i
        "The Callback URL saved in Radar is not the one on your Upwork key. They must match exactly, including the trailing path."
      when /code|grant|expired/i
        "That code has expired or was already used. Codes last a few minutes and work once: approve on Upwork again and paste the new address straight away."
      else
        "Upwork did not accept the sign-in: #{text.first(200)}"
      end
    end

    def description(message)
      json = message.to_s[/\{.*\}/m]
      return message.to_s if json.nil?

      data = JSON.parse(json)
      [ data["error_description"], data["error"] ].compact.join(" ").presence || message.to_s
    rescue JSON::ParserError
      message.to_s
    end
  end
end
