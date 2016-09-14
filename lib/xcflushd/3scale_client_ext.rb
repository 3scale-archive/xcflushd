# We need to configure the ThreeScale::Client::HTTPClient class of the
# 3scale_client gem before we use it.
# Internally, the 3scale_client uses Net::HTTP with the keep-alive option
# enabled when it is available and the net-http-persistent gem
# https://github.com/drbrain/net-http-persistent when it is not.
# The first option is not thread-safe, and the second one is. This is why we
# need to force the second option.

require 'net/http/persistent'

ThreeScale::Client::HTTPClient.persistent_backend =
    ThreeScale::Client::HTTPClient::NetHttpPersistent
