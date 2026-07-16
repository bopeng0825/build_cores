FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    unzip \
    xz-utils \
    ca-certificates \
    make \
    cmake \
    python3 \
    python3-pip \
    pkg-config \
    file \
 && rm -rf /var/lib/apt/lists/*


WORKDIR /opt


RUN wget -O toolchain.tar.gz \
    https://github.com/game-de-it/sf3000/releases/download/sf3000_toolchain_v0.1/mipsel-buildroot-linux-gnu_sdk-buildroot.tar.gz \
 && tar xf toolchain.tar.gz \
 && rm toolchain.tar.gz


ENV TOOLCHAIN=/opt/mipsel-buildroot-linux-gnu_sdk-buildroot

ENV PATH=$TOOLCHAIN/opt/ext-toolchain/bin:$PATH


WORKDIR /work


CMD ["/bin/bash"]