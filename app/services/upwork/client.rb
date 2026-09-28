require "net/http"
require "uri"

module Upwork
  # Owns OAuth2 token lifecycle and GraphQL transport. Nothing else.
  #
  # Endpoints confirmed against Upwork's own SDK (upwork/node-upwork-oauth2,
  # lib/config.js, pushed 2026-08-21).
  class Client
    AUTHORIZE_URL = "https://www.upwork.com/ab/account-security/oauth2/authorize".freeze
    TOKEN_URL     = "https://www.upwork.com/api/v3/oauth2/token".freeze
    GRAPHQL_URL   = "https://api.upwork.com/graphql".freeze

    # Entered in setup and stored encrypted. They used to come from
    # config/credentials.yml.enc, which nobody but its author could decrypt.
    def self.credentials
      Credential.upwork
    end

    def self.configured?
      credentials[:client_id].present? && credentials[:client_secret].present?
    end

    def initialize(store: TokenStore.new)
      @store = store
    end

    def self.authorize_url(state: SecureRandom.hex(8))
      params = {
        response_type: "code",
        client_id: credentials[:client_id],
        redirect_uri: credentials[:redirect_uri],
        state: state
      }
      "#{AUTHORIZE_URL}?#{params.to_query}"
    end

    # Upwork sends the browser back to the callback address with ?code=...
    # That page does not need to load: the person pastes the address they
    # landed on, or just the code, and this finds it either way.
    def self.code_from(text)
      text = text.to_s.strip
      return nil if text.blank?

      if text.include?("code=")
        query = text.include?("?") ? text.split("?", 2).last : text
        return ::URI.decode_www_form(query.split("#").first).to_h["code"].presence
      end

      text.match?(/\A[\w\-.~]+\z/) ? text : nil
    rescue ArgumentError
      nil
    end

    # Exchange the pasted verifier code for a token pair. Mirrors the
    # out-of-band flow the official SDK example uses, which sidesteps the
    # question of whether Upwork accepts an http://localhost redirect.
    def exchange_code(code)
      post_token(
        grant_type: "authorization_code",
        code: code,
        redirect_uri: self.class.credentials[:redirect_uri]
      )
    end

    def query(document, variables = {})
      body = { query: document, variables: variables }
      response = post_json(GRAPHQL_URL, body, authorized_headers)

      raise RateLimited, "Upwork rate limited the request" if response.code.to_i == 429
      raise AuthError, "Upwork rejected the token" if response.code.to_i == 401

      # A gateway in front of Upwork answers with plain text, not JSON, when it
      # is unhealthy: "upstream connect error", "upstream request timeout". That
      # is a transient network condition wearing an HTTP status, so it belongs
      # with the timeouts rather than escaping as a JSON::ParserError and taking
      # the whole poll cycle down with it.
      raise TransportError, "Upwork returned #{response.code}: #{snippet(response)}" if response.code.to_i >= 500

      parsed = parse_json!(response)
      if parsed["errors"].present?
        raise Error, parsed["errors"].map { |e| e["message"] }.join("; ")
      end

      parsed.fetch("data", {})
    end

    private

    def authorized_headers
      headers = {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type"  => "application/json"
      }
      tenant = self.class.credentials[:tenant_id]
      headers["X-Upwork-API-TenantId"] = tenant if tenant.present?
      headers
    end

    def access_token
      refresh! if @store.expired?
      @store.access_token.presence || raise(AuthError, "Upwork is not connected yet. Finish the Connect Upwork step in Setup.")
    end

    def refresh!
      raise AuthError, "Upwork's sign-in has expired and cannot renew itself. Reconnect Upwork in Settings." if @store.refresh_token.blank?

      post_token(grant_type: "refresh_token", refresh_token: @store.refresh_token)
    end

    def post_token(**params)
      raise AuthError, "No Upwork API key saved. Add it in Setup." unless self.class.configured?

      creds = self.class.credentials
      payload = params.merge(client_id: creds[:client_id], client_secret: creds[:client_secret])
      response = post_form(TOKEN_URL, payload)
      raise AuthError, "Token request failed: #{response.code} #{response.body.to_s.first(300)}" unless response.code.to_i == 200

      data = parse_json!(response)
      @store.save!(
        access_token: data["access_token"],
        refresh_token: data["refresh_token"],
        expires_at: Time.current + data.fetch("expires_in", 3600).to_i.seconds
      )
      data
    end

    # Upwork always answers JSON when it answers at all. Anything else came from
    # infrastructure in front of it and is worth one more try, not a dead cycle.
    def parse_json!(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise TransportError, "Upwork returned #{response.code} but not JSON: #{snippet(response)}"
    end

    def snippet(response) = response.body.to_s.gsub(/\s+/, " ").strip.first(120)

    def post_json(url, body, headers)
      http_post(url, body.to_json, headers)
    end

    def post_form(url, params)
      http_post(url, ::URI.encode_www_form(params), { "Content-Type" => "application/x-www-form-urlencoded" })
    end

    def http_post(url, body, headers)
      attempts = 0
      begin
        attempts += 1
        perform_post(url, body, headers)
      rescue *TRANSPORT_FAILURES => e
        retry if attempts < 2
        raise TransportError, "#{e.class}: #{e.message}"
      end
    end

    def perform_post(url, body, headers)
      uri = ::URI.parse(url)
      http = ::Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      request = ::Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = body
      http.request(request)
    end
  end
end
