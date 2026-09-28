require "test_helper"

# The Upwork key used to live in config/credentials.yml.enc, which a fresh
# clone cannot decrypt. It lives in the database now, and must be encrypted
# there: a copied development.sqlite3 should not hand anyone the key.
class CredentialTest < ActiveSupport::TestCase
  test "values are encrypted at rest" do
    Credential.set("upwork.client_secret", "s3cret-value-123")

    raw = Credential.connection.select_value("SELECT value FROM credentials WHERE key = 'upwork.client_secret'")
    assert_not_includes raw, "s3cret-value-123"
    assert_equal "s3cret-value-123", Credential.get("upwork.client_secret")
  end

  test "upwork returns the shape the client has always read" do
    Credential.set_upwork(client_id: "id-1", client_secret: "sec-1", redirect_uri: "https://example.com/cb")

    assert_equal({ client_id: "id-1", client_secret: "sec-1", redirect_uri: "https://example.com/cb" }, Credential.upwork)
    assert Upwork::Client.configured?
  end

  test "blank clears a value so an optional field can be removed" do
    Credential.set("upwork.tenant_id", "t-1")
    Credential.set("upwork.tenant_id", "")

    assert_nil Credential.get("upwork.tenant_id")
  end

  test "a saved secret is shown masked, never whole" do
    Credential.set("upwork.client_secret", "abcd1234efgh5678")

    assert_equal "abcd••••5678", Credential.masked("upwork.client_secret")
    assert_nil Credential.masked("upwork.nothing")
  end

  test "values are stripped of the whitespace a paste brings with it" do
    Credential.set("upwork.client_id", "  id-with-spaces \n")
    assert_equal "id-with-spaces", Credential.get("upwork.client_id")
  end
end
