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

This section describes both verification and signing of docker image.

#### Verification

The authenticity of an image can be verified using the signature attached to each release at the GitHub [Releases page](https://github.com/3scale/xcflushd/releases) (starting from version `v1.2.1`). The signature file has a predefined name: `xcflushd-image-<DOCKER_VERSION>.signature`.

The signature is generated using a PGP private key. The corresponding PGP public key is published to PGP keyservers for retrieval and usage in image verification.

The process of verification involves details such as fetching keys from PGP keyring, subkeys, inspecting the docker image etc. The Makefile in the project directory simplifies this process of verification using two makefile targets:
* verify
* verify-docker

Either of these targets will perform verification and print a pass/fail message. The use of these target is described in more detail in later sections.

The above Makefile targets use the following tools for verification:

* [GnuPG 2](https://www.gnupg.org) : OpenPGP encryption and signing tool.  This is used to fetch the published PGP public keys and add them to the PGP keyring.
* [Skopeo](https://github.com/projectatomic/skopeo):  A command line utility that provides various operations with container images and container registries. This utility is used to verify the authenticity using the PGP public key, the image and the signature from the Docker hub.

##### Makefile target: verify
To verify an  image ( e.g. `3scale/xcflushd:1.2.1-1` ), run:

> make TAG=1.2.1 DOCKER_REL=1 verify

You could also specify a particular `KEY_ID` to check against.
Run `make info` to get information about other variables.

The `verify` target assumes that GnuPG 2 and Skopeo are installed and searches for `gpg2` and `skopeo` utilities on the bash shell command path. On some RPM-based OS, `gpg2` and/or `skopeo` are either installed or easily installable using a packet manager. Verification using the verify target is fairly simple to use. On other OS ( e.g non RPM based ), installing nuPG 2 and Skopeo can be more complicated. On such systems verification using the verify `verify-docker` target is probably easier to use than the `verify` target.

To install gpg2 and skpeo on Red Hat Enterprise Linux (RHEL), use the following instructions.
1. gpg2 is installed by default.
1. skopeo can be installed as follows:
   * sudo yum repolist all ## List all repositories
   * Find the \*-extras repository
   * sudo yum-config-manager --enable rhui-REGION-rhel-server-extras # Enable extras repository
   * sudo yum install skopeo

The `verify` target :
* If an ASCII armored file $(KEY_ID).asc exists, then the keys are imported form this file into the PGP ring. The PGP keys are imported from the PGP servers only if the $(KEY_ID).asc files does not exist. $(KEY_ID) is the value of the PGP Key ID that was used in signing of the docker image.
* Fetches PGP public keys associated with the KEY_ID into  from the PGP ring, iterates over them and uses skopeo tool to verify the authenticity of the image.
* Sucess/failure message is printed.

##### Makefile target: verify-docker

The verify-docker target builds a Docker image that can verify other docker-images. This method is easy to use on any OS but particularly useful on OS where gpg2 and skopeo tools are not easy to install.

This requires Docker and GNU Make.

The command you want to run for verifying the docker release 1 of v1.2.1 is:

> make TAG=1.2.1 DOCKER_REL=1 verify-docker

You could also specify a particular `KEY_ID` to check against.
Run `make info` to get information about other variables.

#### Signing The Easy Way

For signing you basically want to have an ASCII armored file with the pair of
private and public keys. The process expects a `$(KEY_ID).asc` file to be
imported in the project's root directory.

Using Docker you can avoid installing dependencies:

> make TAG=1.2.1 DOCKER_REL=1 sign-docker

#### Verification Image Shell

You can use the normal make targets (sign and verify) if you invoke

> make verify-image-shell

The results of your actions will be synchronized with the host files.

##### Signing

If you want to generate a signature file, you have to provide a file with the
secret key, see `make info` for variables that specify its location.

By default, a filename with the `KEY_ID` variable and an extension of `.asc`
will be imported if existing, and then be used to sign the image.

> make TAG=1.2.1 DOCKER_REL=1 KEY_ID=0x123456 sign

(imports 0x123456.asc file)

##### Verifying

If you want to verify an image you have to provide a signature file, and
optionally a filename in a similar fashion as for signing containing the public
key of the `KEY_ID` variable. If such files are not present the system will try
to fetch the signature file from Github and the key from the PGP servers.

> make TAG=1.2.1 DOCKER_REL=1 KEY_ID=0x123456 verify

## Contributing

1. Fork the project
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Create a new Pull Request


## License

[Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
