require "test_helper"

# The failure this covers: Upwork's gateway answered a poll with the plain text
# "upstream connect error", JSON.parse raised, and the exception escaped the
# poll job's `rescue Upwork::Error`. One unhealthy gateway cost a whole cycle.
class UpworkClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  # Everything below the HTTP call is the real client. Only the socket is faked.
  class FakeTransport < Upwork::Client
    def initialize(response) = @response = response
    def post_json(*) = @response
    def authorized_headers = {}
  end

  def query_returning(code, body) = FakeTransport.new(Response.new(code, body)).query("{ x }")

  test "a non-JSON body is a transport failure, not a parse crash" do
    error = assert_raises(Upwork::TransportError) do
      query_returning("200", "upstream connect error or disconnect/reset before headers")
    end
    assert_match "not JSON", error.message
    assert_kind_of Upwork::Error, error, "the poll job rescues Upwork::Error, so it must be one"
  end

  test "a 5xx is a transport failure even when it is valid JSON" do
    assert_raises(Upwork::TransportError) { query_returning("503", '{"message":"Service unavailable"}') }
  end

  test "429 still reads as rate limiting" do
    assert_raises(Upwork::RateLimited) { query_returning("429", "slow down") }
  end

  test "401 still reads as an auth failure" do
    assert_raises(Upwork::AuthError) { query_returning("401", "nope") }
  end

  test "a GraphQL error is reported as itself, not as transport" do
    error = assert_raises(Upwork::Error) { query_returning("200", '{"errors":[{"message":"Underling search failed"}]}') }
    assert_not_kind_of Upwork::TransportError, error
    assert_match "Underling search failed", error.message
  end

  test "a good response parses" do
    assert_equal({ "marketplaceJobPostingsSearch" => { "edges" => [] } },
                 query_returning("200", '{"data":{"marketplaceJobPostingsSearch":{"edges":[]}}}'))
  end
end
