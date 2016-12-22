# DESIGN

## Description

xcflushd is a daemon used together with [XC](https://github.com/3scale/apicast-xc),
which is a module for [APIcast](https://github.com/3scale/apicast), 3scale's
API Gateway.

If you are not familiar with XC yet, we recommend you to start reading its
documentation before reading this document.

In XC, the xcflushd daemon is responsible for these three things:

* Reporting to 3scale's backend the reports cached in XC.
* Updating the status of the authorizations cached in XC.
* Retrieving an authorization status from 3scale's backend when the
  authorization is not cached in XC.

It is important to keep in mind that the first 2 always happen in background,
while the third happens in request time.


## How xcflushd works

Once xcflushd starts, it will:

* Start "flushing" periodically to 3scale.
* Start listening in a the Redis pubsub channel that XC uses to ask for
  authorizations that are not cached.

Let us explain those 2 operations in more detail.


### Periodic flushing

The flushing consists of 4 steps:

1. Retrieve the cached reports from Redis.
2. Send those cached reports to 3scale's backend.
3. Wait for a few seconds.
4. Renew the cached authorizations in Redis of the applications that appear in
   the reports that have just been sent to 3scale.

You might be wondering why there's a waiting time between sending the cached
reports and renewing the cached authorizations. The reason is that reporting is
asynchronous in 3scale's backend API. That means that, when reporting, we'll
get an OK http response code if our reports do not contain any format errors
and the credentials are OK, but we do not have a way to know when those reports
are effective and considered for rate limiting. We know that 3scale is pretty
quick doing that, though! This is a trade-off that 3scale makes between
request latency and accurateness of rate limits.

Another important thing is that when renewing cached authorizations, xcflushd
does not only renew the ones of the metrics that appear in the cached reports.
The call to 3scale backend allows us to ask for the limits of most of the
metrics of an application, so we take advantage of that and renew all the ones
we can in one network round-trip. More specifically, the ones that are not
renewed are the ones that meet these two conditions: 1) have not been included
in the reports sent to 3scale's backend, and 2) do not have any limits defined.

The whole flushing process makes 2 calls to 3scale per application reported.
One call to send the report to 3scale, and another one to get the current
authorization status. Compare that to making one request for each one that
arrives to the proxy as in the case of APIcast. Imagine that you have 1k rps,
and 100 apps. If you define a period of 1 minute for the flushing process, you
will be making 200 requests to 3scale's backend per minute instead of 60k.

We use the [3scale client gem](https://github.com/3scale/3scale_ws_api_for_ruby)
to make the requests to 3scale's backend.


### Requests via Redis pubsub

xcflushd offers a mechanism that allows clients to ask for a specific
authorization status without having to wait for the next flush cycle. This
mechanism is based on Redis pubsub.

xcflushd subscribes to a channel to which clients publish messages with a
`(service, app credentials, metric)` tuple encoded. When xcflushd receives one
of those messages, it makes a request to the 3scale backend to check the
authorization status of the given `(service, app credentials, metric)` tuple,
and it publishes the result to another pubsub channel to which clients need to
subscribe. To make the most out of this network round-trip to 3scale's backend,
we take the opportunity to store in the Redis cache the authorization statuses
that we just retrieved. Although the message only contained one metric, we
renew all the ones we can get in a single request to 3scale's backend. Just
like we do in the case of the periodic flushing detailed above.

xcflushd might receive several requests at the same time about the same
`(service, app credentials, metric)` tuple. xcflushd takes this into account
and does not make extra requests to 3scale's backend for authorizations that
are already being checked.


## Redis keys

The format of the Redis keys used is specified in the `Xcflushd::StorageKeys`
class. The keys need to follow the same format as the one defined in the XC
lua module. Check the [XC lua module design doc](https://github.com/3scale/apicast-xc/blob/master/doc/design.md#redis-keys-format)
for more info about this.
