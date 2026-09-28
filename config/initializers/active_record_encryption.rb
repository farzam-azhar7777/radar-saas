# Keys for encrypting the Upwork credentials at rest.
#
# They used to live in config/credentials.yml.enc, which a fresh clone cannot
# decrypt without someone else's master key. Instead each install generates its
# own keys on first boot, into storage/ (gitignored, chmod 600). Losing the file
# only means entering the Upwork key again; nothing else is encrypted.
require "securerandom"

keys =
  if Rails.env.test?
    { "primary_key" => "t" * 32, "deterministic_key" => "d" * 32, "key_derivation_salt" => "s" * 32 }
  else
    path = Rails.root.join("storage", "encryption.json")
    unless path.exist?
      FileUtils.mkdir_p(path.dirname)
      File.write(path, JSON.pretty_generate(
        "primary_key" => SecureRandom.alphanumeric(32),
        "deterministic_key" => SecureRandom.alphanumeric(32),
        "key_derivation_salt" => SecureRandom.alphanumeric(32)
      ))
      File.chmod(0o600, path)
    end
    JSON.parse(path.read)
  end

Rails.application.config.active_record.encryption.primary_key = keys.fetch("primary_key")
Rails.application.config.active_record.encryption.deterministic_key = keys.fetch("deterministic_key")
Rails.application.config.active_record.encryption.key_derivation_salt = keys.fetch("key_derivation_salt")
