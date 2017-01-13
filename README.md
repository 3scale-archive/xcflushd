# Xcflushd

[![Build Status](https://travis-ci.org/3scale/xcflushd.svg?branch=master)](https://travis-ci.org/3scale/xcflushd) [![Code Climate](https://codeclimate.com/repos/585a6e7cd78de855e5002463/badges/7825d2a1491b30a172f7/gpa.svg)](https://codeclimate.com/repos/585a6e7cd78de855e5002463/feed)

## Description

This is the daemon that flushes the data that the gateway side of XC like the
[apicast-xc](https://github.com/3scale/apicast-xc) module running on top of [APIcast](https://github.com/3scale/apicast), stores for reporting and authorizing to 3scale.

When you deploy 3scale to a gateway you usually have a request performed to
3scale for every request that needs authorization, which introduces latency and
load in 3scale. The goal of XC is to reduce latency and increase throughput by
significantly reducing the number of requests made to 3scale's backend. In
order to achieve that, XC caches authorization statuses and reports.

Xcflushd is a daemon that is required to run while using XC. Its responsibility
consists of flushing the cached reports and renewing the cached authorization
statuses. All this is done in background, not in request time.

Xcflushd can run together with a different gateway as long as it uses the same
format for the cached authorizations and reports. This format will be
documented soon.

## Development environment and testing

You will need [Docker](https://www.docker.com/) and GNU make.

First, clone the project:
```
$ git clone git@github.com:3scale/xcflushd.git
```

Next, cd into the directory, `cd xcflushd`

Run the tests with:
```
$ make test
```

That will run the unit test suite. It's using [Rspec](https://rspec.info).

Develop with:
```
$ make bash
```

That will create a Docker container and run bash inside it. The project's
source code will be available in `~/app` and synced with your local xcflushd
directory. You can edit files in your preferred environment and still be able
to run whatever you need inside the Docker container.


## Deployment

You will need a Redis server running.

### Docker

Build:
```
$ make build
```

Run:
```
$ docker run --rm xcflushd bundle exec xcflushd help run
```

You can send the options as params in the `xcflushd` command:
```
$ docker run --rm -it xcflushd bundle exec xcflushd run --auth-ttl 900 --provider-key my_provider_key --redis 127.0.0.1:6379 --frequency 300 --backend https://su1.3scale.net:443
```

Please note that the help command will also show you abbreviated flags you can
use at your convenience.

### Locally

Install the dependencies:
```
$ bundle install
```

Run the program:
```
$ bundle exec xcflushd help
```

### Openshift

If what you need is deploying Xcflushd together with APIcast and XC, you can
follow the instructions provided in the [apicast-xc repo](https://github.com/3scale/apicast-xc).


## How it works

Every X minutes (configurable) the flusher does two things:

1. Reports to 3scale all the reports cached in Redis.
2. Renews the authorization status (authorized/denied) for all the
   applications affected by the cached reports that have been reported to
   3scale.

For more details, check the [design doc](docs/design.md).


## Contributing

1. Fork the project
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Create a new Pull Request


## License

[Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
