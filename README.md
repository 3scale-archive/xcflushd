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

You can also customize the test command with:
```
$ make TEST_CMD=my_test_script test
```

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

You can use `make build` to build Docker images. Run `make info` to obtain
information about variables that control this process as well as other targets.

Build:
```
$ make build
```

You can specify Dockerfile arguments like this:

```
$ make DOCKER_BUILD_ARGS="--build-arg RBENV_VERSION=v1.1.0 --build-arg RBENV_RUBYBUILD_VERSION=v20170523 --build-arg GEM_UPDATE=true" build
```

Check the Dockerfile for variables you can set that affect the build.

Run:
```
$ docker run --rm -it xcflushd script/launch help
```

You can send the options as params for `script/launch`:
```
$ docker run --rm -it xcflushd script/launch run --auth-ttl 900 --provider-key my_provider_key --redis 127.0.0.1:6379 --frequency 300 --backend https://su1.3scale.net:443
```

Please note that the help command will also show you abbreviated flags you can
use at your convenience. Also, `script/launch` sets all the JRuby flags
recommended for a production environment. If you'd like to set different ones,
you can run:
```
$ docker run --rm -it xcflushd JRUBY_OPTS="..." jruby -S bundle exec xcflushd help
```

### Locally

This instructions are for JRuby, the Ruby implementation that we recommend for
running xcflushd.

Install the dependencies:
```
$ jruby -S bundle install
```

Run the program with the recommended flags for production:
```
$ script/launch help
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

## Official Docker images

Official Docker images are pushed to Docker Hub on release. We tag each image
with the xcflushd version and a Docker release number. The Docker release number
is bumped when a new image is uploaded with no changes in the code but just the
image or packaging details.

### Image Authenticity

The image can be verified using the signature attached to each release at the GitHub [Releases page](https://github.com/3scale/xcflushd/releases) (starting from version `v1.2.1`). The signature file has a predefined name: `xcflushd-image-<DOCKER_VERSION>.signature`.

#### Verification The Easy Way

If you want to go the easy way and build a Docker image that can verify other
Docker images, this is how to do it. If you prefer a more manual process to
understand the details, skip to the next section.

This requires Docker and GNU Make.

The command you want to run is:

> make TAG=v1.2.1 DOCKER_REL=1 verify-docker

You could also specify a particular `KEY_ID` to check against.
Run `make info` to get information about other variables.

#### Verification The Not So Easy Way

##### Requirements

For this to work you will need [GnuPG 2](https://www.gnupg.org) and [Skopeo](https://github.com/projectatomic/skopeo), and you will need to import
the `Red Hat 3scale API Management Platform Signing Key` public key into your
GnuPG keyring. Such key is available on the usual PGP servers.

Please refer to the [GnuPG documentation](https://www.gnupg.org/documentation/index.html) for details about importing the key.

You will also need to place the relevant `.signature` file from the release page in the main directory of the cloned repository.

##### Verification

You can verify the images if you so desire. For example, to verify
`3scale/xcflushd:1.2.1-1`, you would run:

> make TAG=v1.2.1 DOCKER_REL=1 verify

You could also specify a particular `KEY_ID` to check against.
Run `make info` to get information about other variables.

#### Signing The Easy Way

For signing you basically want to have an ASCII armored file with the pair of
private and public keys. The process expects a `$(KEY_ID).asc` file to be
imported in the project's root directory.

Using Docker you can avoid installing dependencies:

> make TAG=v1.2.1 DOCKER_REL=1 sign-docker

#### Verification Image Shell

You can use the normal make targets (sign and verify) if you invoke

> make verify-image-shell

The results of your actions will be synchronized with the host files.

##### Signing

If you want to generate a signature file, you have to provide a file with the
secret key, see `make info` for variables that specify its location.

By default, a filename with the `KEY_ID` variable and an extension of `.asc`
will be imported if existing, and then be used to sign the image.

> make TAG=v1.2.1 DOCKER_REL=1 KEY_ID=0x123456 sign

(imports 0x123456.asc file)

##### Verifying

If you want to verify an image you have to provide a signature file, and
optionally a filename in a similar fashion as for signing containing the public
key of the `KEY_ID` variable. If such files are not present the system will try
to fetch the signature file from Github and the key from the PGP servers.

> make TAG=v1.2.1 DOCKER_REL=1 KEY_ID=0x123456 verify

## Contributing

1. Fork the project
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Create a new Pull Request


## License

[Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
