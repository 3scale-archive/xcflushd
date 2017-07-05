FROM ubuntu:xenial
MAINTAINER Alejandro Martinez Ruiz <alex@3scale.net>

ENV DEBIAN_FRONTEND=noninteractive

# User
ARG USER_NAME=user
ARG USER_HOME="/home/${USER_NAME}"
# Timezone
ARG TZ="UTC"

RUN echo "Acquire::http {No-Cache=True;};" > /etc/apt/apt.conf.d/no-cache \
 && echo 'APT {Install-Recommends="false";Install-Suggests="false";};' > /etc/apt/apt.conf.d/no-recommends \
 && rm -f /etc/cron.weekly/fstrim \
 && rm -f /etc/cron.daily/apt \
 && rm -f /etc/cron.daily/dpkg \
 && rm -f /etc/cron.daily/passwd \
 && apt-get update -y -q && apt-get install -y -q apt-utils tzdata \
 && apt-get dist-upgrade -y -q \
 && apt-get install -y -q sudo cron logrotate wget curl unzip ca-certificates \
    iputils-arping inetutils-ping inetutils-telnet net-tools nmap iotop tmux vim \
    build-essential git make strace gdb tcpdump autoconf libtool autopoint bison \
    libssl-dev libcurl4-openssl-dev libz-dev bash \
 && adduser --disabled-password --home ${USER_HOME} --shell /bin/bash \
      --gecos "" ${USER_NAME} \
 && echo "${USER_NAME} ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER_NAME} \
 && chmod 0440 /etc/sudoers.d/${USER_NAME} \
 && passwd -d ${USER_NAME} \
 && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
 && echo ${TZ} > /etc/timezone \
 && dpkg-reconfigure --frontend ${DEBIAN_FRONTEND} tzdata \
 && apt-get -y -q autoremove --purge \
 && chown -R ${USER_NAME}: ${USER_HOME} \
 && apt-get -y -q clean

RUN apt-get install -y -q openjdk-8-jre && apt-get -y -q clean

USER ${USER_NAME}

ARG RBENV_ROOT="${USER_HOME}/.rbenv"
ARG RBENV_BINPATH="${RBENV_ROOT}/bin"
ARG RBENV_PATH="${RBENV_ROOT}/shims:${RBENV_BINPATH}"

ARG RBENV_RUBYBUILD_ROOT=${RBENV_ROOT}/plugins/ruby-build

RUN git clone --recursive --single-branch https://github.com/rbenv/rbenv.git ${RBENV_ROOT} \
 && git clone --recursive --single-branch https://github.com/rbenv/ruby-build.git ${RBENV_RUBYBUILD_ROOT} \
 && cd ${RBENV_ROOT} \
 && ( \
      git checkout -f $(git tag | grep -P "^v?\d[\d.]*$" | sed -e "s/^v//g" | sort -V | tail -n 1) \
       || git checkout -f v$(git tag | grep -P "^v?\d[\d.]*$" | sed -e "s/^v//g" | sort -V | tail -n 1) \
    ) \
 && git submodule update --checkout \
 && cd ${RBENV_RUBYBUILD_ROOT} \
 && ( \
      git checkout -f $(git tag | grep -P "^v?\d[\d.]*$" | sed -e "s/^v//g" | sort -V | tail -n 1) \
       || git checkout -f v$(git tag | grep -P "^v?\d[\d.]*$" | sed -e "s/^v//g" | sort -V | tail -n 1) \
    ) \
 && cd ${RBENV_ROOT} && src/configure && ( make -C src || true ) \
 && echo -n export PATH=${RBENV_BINPATH} >> ~/.bash_rbenv && echo ':$PATH' >> ~/.bash_rbenv \
 && echo 'eval "$(rbenv init -)"' >> ~/.bash_rbenv \
 && echo 'source ~/.bash_rbenv' >> ~/.profile

ARG APP_HOME=${USER_HOME}/app
ARG BUILD_DEPS="libyaml-dev libreadline-dev libncurses-dev libffi-dev libgdbm3 libgdbm-dev"

USER root
RUN test -z "${BUILD_DEPS}" \
 || ( \
      apt-get update && apt-get install -y -q ${BUILD_DEPS} && apt-get -y -q clean \
    )

WORKDIR ${APP_HOME}
COPY .ruby-version .ruby-gemset ${APP_HOME}/

USER ${USER_NAME}
ENV PATH="${RBENV_PATH}:${PATH}"
RUN rbenv install -s \
 && rbenv rehash \
 && echo 'gem: --no-document' >> ~/.gemrc \
 && gem update --system  \
 && ( bundler --version || gem install bundler ) \
 && bundle config --global jobs `grep -c processor /proc/cpuinfo` \
 && bundle config --global cache_all true \
 && gem cleanup all

COPY Gemfile Gemfile.lock xcflushd.gemspec ${APP_HOME}/
COPY lib/xcflushd/version.rb ${APP_HOME}/lib/xcflushd/
USER root
RUN chown -R ${USER_NAME}: ${APP_HOME}

USER ${USER_NAME}
RUN bundle install

COPY . ${APP_HOME}
USER root
RUN chown -R ${USER_NAME}: ${APP_HOME}

USER ${USER_NAME}

# ensure executable bits are preserved and install dependencies
RUN find script/ bin/ -maxdepth 1 -type f | xargs chmod +x \
 && bundle install

ARG JRUBY_EXEC="jruby -Xcompile.invokedynamic=true -J-XX:ReservedCodeCacheSize=256M -J-XX:+UseCodeCacheFlushing -J-Xmn512m -J-Xms2048m -J-Xmx2048m -J-server -J-Djruby.objectspace.enabled=false -J-Djruby.thread.pool.enabled=true -J-Djruby.thread.pool.ttl=600 -J-Djruby.compile.mode=FORCE --server --headless -S"
CMD ${JRUBY_EXEC} bundle exec exe/xcflushd run
