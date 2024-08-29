FROM ubuntu:jammy AS build
ENV DEBIAN_FRONTEND=noninteractive
ENV OS=linux
ENV ARCH=amd64

# Create workdir
RUN mkdir /build

# Install global build dependencies
RUN \
  apt-get update && \
  apt-get install -y \
    git \
    pkg-config \
    libtool \
    automake \
    cmake

# Build usrsctp from sources
RUN \
  cd /build && \
  git clone https://github.com/sctplab/usrsctp && \
  cd usrsctp && \
  git reset --hard a07d9a846480f072fe53cd9f55fd014077d532af && \
  cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr/local . && \
  make -j$(nproc) && \
  make install

# Install build dependencies of libsrtp
RUN \
  apt-get update && \
  apt-get install -y \
	  libssl-dev

# Build libsrtp from sources as one shipped with ubuntu does not support AES-GCM profiles
# This needs to use /usr or /usr/local as a prefix.
# See https://github.com/meetecho/janus-gateway/issues/2019
# See https://github.com/meetecho/janus-gateway/issues/2024
RUN \
  cd /build && \
  git clone --branch v2.3.0 https://github.com/cisco/libsrtp.git && \
  cd libsrtp && \
  ./configure --prefix=/usr/local --enable-openssl && \
  make -j$(nproc) shared_library && \
  make install

# Install build dependencies of janus-gateway
RUN \
  apt-get update && \
  apt-get install -y \
    libwebsockets-dev \
    librabbitmq-dev \
    libssl-dev \
    libnice-dev \
    libglib2.0-dev \
    libmicrohttpd-dev \
    libjansson-dev \
    libsofia-sip-ua-dev \
    libopus-dev \
    libogg-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libcurl4-openssl-dev \
    liblua5.3-dev \
    libconfig-dev \
    gengetopt

# Build janus-gateway from sources
RUN \
  cd /build && \
  git clone --branch v1.2.3 https://github.com/meetecho/janus-gateway.git
RUN cd /build/janus-gateway && \
  sh autogen.sh && \
  ./configure --prefix=/usr/local \
    --enable-post-processing \
    --enable-websockets \
    --enable-rabbitmq \
    --disable-all-handlers \
    --enable-rabbitmq-event-handler \
    --enable-gelf-event-handler
RUN cd /build/janus-gateway && \
  make -j$(nproc) && \
  make install && \
  make configs

# Install dependencies of dockerize
RUN \
  apt-get update && \
  apt-get install -y \
    wget

# Install dockerize
ENV DOCKERIZE_VERSION v0.8.0
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-$OS-$ARCH-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-$OS-$ARCH-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-$OS-$ARCH-$DOCKERIZE_VERSION.tar.gz

FROM ubuntu:jammy
ARG app_uid=999
ARG ulimit_nofile_soft=524288
ARG ulimit_nofile_hard=1048576

# Install runtime dependencies of janus-gateway
RUN \
  apt-get update && \
  apt-get install -y \
    libwebsockets16 \
    librabbitmq4 \
    libssl3 \
    libglib2.0-0 \
    libmicrohttpd12 \
    libjansson4 \
    libsofia-sip-ua-glib3 \
    libopus0 \
    libogg0 \
    libavcodec58 \
    libavformat58 \
    libavutil56 \
    libcurl4 \
    libnice10 \
    liblua5.3-0 \
	  libconfig9 && \
 rm -rf /var/lib/apt/lists/*

# Copy all things that were built
COPY --from=build /usr/local /usr/local

# Set ulimits
RUN \
  echo ":${app_uid}	soft	nofile	${ulimit_nofile_soft}" > /etc/security/limits.conf && \
  echo ":${app_uid}	hard	nofile	${ulimit_nofile_hard}" >> /etc/security/limits.conf

# Do not run as root unless necessary
RUN groupadd -g ${app_uid} app && useradd -r -u ${app_uid} -g app app

# Copy entrypoint and config templates
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ADD templates /templates

# Websocket
EXPOSE 8188:8188/tcp
# RTP
EXPOSE 10000-10099:10000-10099/udp
# HTTP Janus API
EXPOSE 8088:8088
# HTTP Admin API
EXPOSE 7088:7088

# Start the gateway
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/usr/local/lib/aarch64-linux-gnu
CMD /entrypoint.sh
