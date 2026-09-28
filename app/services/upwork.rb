require "net/http"
require "uri"

# Errors live here, not inside client.rb, so they resolve whether or not
# Upwork::Client has been autoloaded. A rescue clause that cannot resolve its
# own constant raises NameError instead of rescuing, which is a worse failure
# than the one it was trying to handle.
module Upwork
  class Error < StandardError; end
  class AuthError < Error; end
  class RateLimited < Error; end

  # Timeouts, resets and DNS blips. Transient by nature: skip the query and
  # carry on, rather than letting one bad socket kill the whole poll cycle.
  class TransportError < Error; end

  TRANSPORT_FAILURES = [
    Net::ReadTimeout, Net::OpenTimeout, Net::HTTPBadResponse,
    Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::EPIPE,
    SocketError, OpenSSL::SSL::SSLError, IOError
  ].freeze
end
