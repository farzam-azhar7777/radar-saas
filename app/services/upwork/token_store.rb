module Upwork
  # Tokens live in a gitignored JSON file beside the databases, never in the repo.
  class TokenStore
    # Tests get a file of their own per process, so a test can never read or
    # overwrite a real sign-in.
    def self.path
      return Rails.root.join("tmp", "upwork_tokens_test_#{Process.pid}.json") if Rails.env.test?

      Rails.root.join("storage", "upwork_tokens.json")
    end

    def path = self.class.path

    def data
      @data ||= File.exist?(path) ? JSON.parse(File.read(path)) : {}
    end

    def access_token  = data["access_token"]
    def refresh_token = data["refresh_token"]
    def expires_at    = data["expires_at"] && Time.parse(data["expires_at"])

    # Signed in, or able to sign itself back in.
    def connected? = access_token.present? || refresh_token.present?

    def expired?
      expires_at.blank? || expires_at < 1.minute.from_now
    end

    def save!(access_token:, refresh_token:, expires_at:)
      @data = {
        "access_token" => access_token,
        "refresh_token" => refresh_token.presence || self.refresh_token,
        "expires_at" => expires_at.iso8601
      }
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(@data))
      File.chmod(0o600, path)
      @data
    end

    def clear!
      File.delete(path) if File.exist?(path)
      @data = {}
    end
  end
end
