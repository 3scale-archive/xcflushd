# Xcflushd

## Description

This is a daemon used by [XC](https://github.com/3scale/xc.lua). XC is a module
for [Apicast](https://github.com/3scale/apicast), 3scale's API gateway.

Apicast performs one call to 3scale's backend for each request that it
receives. The goal of XC is to reduce latency and increase throughput by
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

### Docker

We will provide a Dockerfile soon.

### Locally

You will need a Redis server running.

Install the dependencies:
```
$ bundle install
```

Run the program:
```
$ bundle exec exe/xcflushd -h
```

### Openshift

If what you need is deploying Xcflushd together with Apicast and XC, you can
follow the instructions provided in the [xc.lua repo](https://github.com/3scale/xc.lua).


## How it works

Every X minutes (configurable) the flusher does two things:

1. Reports to 3scale all the reports cached in Redis.
2. Renews the authorization status (authorized/denied) for all the
   applications affected by the cached reports that have been reported to
   3scale.

A detailed design document will be provided later.


## Contributing

1. Fork the project
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Create a new Pull Request


## License

[Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
