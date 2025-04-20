set shell := ["sh", "-eu", "-c"]

docker_image := "nixos/nix"
docker_platform := "linux/amd64"
sbc_docker_platform := "linux/arm64"
bootstrap_alpine_image := "bootstrap-alpine-builder:local"
bootstrap_alpine_platform := "linux/amd64"

default:
    @just --list

_docker-build platform attr out_dir:
    #!/bin/sh
    set -eu
    cid="$(docker create \
      --platform '{{ platform }}' \
      --security-opt seccomp=unconfined \
      -v "$PWD":/work:ro \
      -w /work \
      {{ docker_image }} \
      sh -eu -c 'out=$(nix --extra-experimental-features "nix-command flakes" --option filter-syscalls false build "$1" --no-link --print-out-paths); mkdir -p /export; cp -aL "$out/." /export/; chmod -R u+rwX,go+rX /export' \
      sh '{{ attr }}')"
    cleanup() { docker rm -f "$cid" >/dev/null 2>&1 || true; }
    trap cleanup EXIT INT TERM
    docker start -a "$cid"
    chmod -R u+w '{{ out_dir }}' 2>/dev/null || true
    rm -rf '{{ out_dir }}'
    mkdir -p '{{ out_dir }}'
    docker cp "$cid:/export/." '{{ out_dir }}/'
    printf 'copied container output to %s\n' '{{ out_dir }}'

# Build the bootable nixos-anywhere installer ISO.
installer-iso:
    just _docker-build {{ docker_platform }} .#installer-iso result/installer-iso

# Build the nixos-anywhere PXE/netboot assets.
installer-netboot:
    just _docker-build {{ docker_platform }} .#installer-netboot result/installer-netboot

# Build both installer artifacts.
installers: installer-iso installer-netboot

# Build the reusable Rock Pi 4B+ bootstrap image.
sbc-rockpi-4b:
    just _docker-build {{ sbc_docker_platform }} .#rockpi-4b-bootstrap-image result/sbc-rockpi-4b

# Build the reusable Rock 5A bootstrap image.
sbc-rock-5a:
    just _docker-build {{ sbc_docker_platform }} .#rock-5a-bootstrap-image result/sbc-rock-5a

# Build the reusable Orange Pi 6 Plus bootstrap image.
sbc-orange-pi-6-plus:
    just _docker-build {{ sbc_docker_platform }} .#orange-pi-6-plus-bootstrap-image result/sbc-orange-pi-6-plus

# Build bootstrap images for every supported SBC model.
sbc-images: sbc-rockpi-4b sbc-rock-5a sbc-orange-pi-6-plus

# Build the Docker image used to produce the customized Alpine bootstrap ISO.
bootstrap-alpine-builder:
    docker build \
      --platform {{ bootstrap_alpine_platform }} \
      -f bootstrap/alpine/Dockerfile \
      -t {{ bootstrap_alpine_image }} \
      bootstrap

# Build the headless Alpine bootstrap ISO and iPXE assets for nixos-anywhere.
bootstrap-alpine: bootstrap-alpine-builder
    #!/bin/sh
    set -eu
    cid="$(docker create --platform {{ bootstrap_alpine_platform }} {{ bootstrap_alpine_image }})"
    cleanup() { docker rm -f "$cid" >/dev/null 2>&1 || true; }
    trap cleanup EXIT INT TERM
    docker start -a "$cid"
    chmod -R u+w result/bootstrap-alpine 2>/dev/null || true
    rm -rf result/bootstrap-alpine
    mkdir -p result/bootstrap-alpine
    docker cp "$cid:/export/." result/bootstrap-alpine/
    printf 'copied Alpine bootstrap artifacts to %s\n' result/bootstrap-alpine
