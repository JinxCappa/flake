#!/bin/sh
set -eu

out_dir=/export
repository="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}"

mkdir -p /root/.abuild "$out_dir"
export PACKAGER="NixOS Bootstrap <bootstrap@localhost>"
abuild-keygen -a -n

PACKAGER_PRIVKEY="$(find /root/.abuild -type f -name '*.rsa' | head -n 1)"
if [ -z "$PACKAGER_PRIVKEY" ]; then
  echo "failed to generate an Alpine package signing key" >&2
  exit 1
fi
export PACKAGER_PRIVKEY
export PACKAGER_PUBKEY="${PACKAGER_PRIVKEY}.pub"
cp "$PACKAGER_PUBKEY" /etc/apk/keys/

cd /root/.mkimage
/aports/scripts/mkimage.sh \
  --tag "$ALPINE_VERSION" \
  --outdir "$out_dir" \
  --arch x86_64 \
  --profile bootstrap \
  --repository "$repository/main" \
  --repository "$repository/community" \
  --checksum

iso="$(find "$out_dir" -maxdepth 1 -type f -name '*.iso' | head -n 1)"
if [ -z "$iso" ]; then
  echo "failed to locate the generated Alpine ISO" >&2
  exit 1
fi

ipxe_dir="$out_dir/ipxe"
mkdir -p "$ipxe_dir"

xorriso -osirrox on -indev "$iso" \
  -extract /boot/vmlinuz-lts "$ipxe_dir/vmlinuz-lts" \
  -extract /boot/initramfs-lts "$ipxe_dir/initramfs-lts" \
  -extract /boot/modloop-lts "$ipxe_dir/modloop-lts" \
  -extract /bootstrap.apkovl.tar.gz "$ipxe_dir/bootstrap.apkovl.tar.gz"

sed "s/@ALPINE_VERSION@/$ALPINE_VERSION/g" \
  /root/.mkimage/boot.ipxe > "$ipxe_dir/boot.ipxe"

(
  cd "$ipxe_dir"
  sha256sum \
    boot.ipxe \
    bootstrap.apkovl.tar.gz \
    initramfs-lts \
    modloop-lts \
    vmlinuz-lts > SHA256SUMS
)
