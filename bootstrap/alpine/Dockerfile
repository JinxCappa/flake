ARG ALPINE_VERSION=3.24
FROM alpine:${ALPINE_VERSION}

ARG ALPINE_VERSION
ARG ALPINE_BRANCH=3.24-stable
ENV ALPINE_VERSION=${ALPINE_VERSION}

RUN apk add --no-cache \
      abuild \
      alpine-conf \
      alpine-sdk \
      apk-tools \
      fakeroot \
      git \
      grub \
      grub-efi \
      mtools \
      squashfs-tools \
      syslinux \
      xorriso \
    && git clone --depth 1 --branch "${ALPINE_BRANCH}" \
      https://gitlab.alpinelinux.org/alpine/aports.git /aports \
    && sed -i 's/add --initdb --no-chown/add --initdb/' /aports/scripts/mkimage.sh

COPY alpine/build.sh /usr/local/bin/build-bootstrap-alpine
COPY alpine/mkimg.bootstrap.sh /root/.mkimage/mkimg.bootstrap.sh
COPY alpine/genapkovl-bootstrap.sh /root/.mkimage/genapkovl-bootstrap.sh
COPY alpine/boot.ipxe /root/.mkimage/boot.ipxe
COPY authorized_keys /root/.mkimage/authorized_keys

RUN chmod +x \
      /usr/local/bin/build-bootstrap-alpine \
      /root/.mkimage/genapkovl-bootstrap.sh

WORKDIR /aports
ENTRYPOINT ["/usr/local/bin/build-bootstrap-alpine"]
