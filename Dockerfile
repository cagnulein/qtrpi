FROM debian:stable-slim
LABEL maintainer="Alexander Rose <alex@rose-a.de>" 

# set qt version and target device via --build-arg
ARG qt_version='5.6.2'
ARG target_device='rpi3'

# Setup Qtrpi environment
ENV QTRPI_QT_VERSION=$qt_version \
    QTRPI_TARGET_DEVICE=$target_device \
    QTRPI_TARGET_HOST='pi@localhost' \
    QTRPI_DOCKER='True' \
    QTRPI_TAG=${target_device}_qt-${qt_version}

# install necessary packages
RUN apt-get update -q && apt-get install -yq --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    g++ \
    gdb-multiarch \
    git \
    qemu-user-static \
    tar \
    unzip \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Change workdir
WORKDIR /opt/qtrpi

# Extract sysroot and binaries
COPY sysroot-minimal.tar.gz ./
COPY qtrpi_${QTRPI_TAG}.tar.gz ./
RUN tar -xzf sysroot-minimal.tar.gz -C / && \
    tar -xzf qtrpi_${QTRPI_TAG}.tar.gz -C / && \
    rm *.tar.gz

# Setup Qt
COPY utils/common.sh utils/
COPY utils/init-common.sh utils/
COPY utils/switch-sysroot.sh utils/
COPY utils/synchronize-toolchain.sh utils/
RUN mkdir -p raspi raspbian bin logs && \
    ./utils/switch-sysroot.sh minimal && \
    ./utils/synchronize-toolchain.sh && \
    rm -rf /opt/qtrpi/raspi/tools/.git && \
    rm -rf /opt/qtrpi/raspi/tools/arm-bcm2708/arm-* && \
    rm -rf /opt/qtrpi/raspi/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian

# Extend path
ENV PATH=/opt/qtrpi/bin:$PATH

COPY utils/docker-build.sh utils/

# Create path for source files
WORKDIR /source

# Execute build commands on run
CMD /opt/qtrpi/utils/docker-build.sh
