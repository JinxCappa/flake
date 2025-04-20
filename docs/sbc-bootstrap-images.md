# SBC bootstrap images

Bootstrap images are hardware-specific, not role- or machine-specific. Flash one
image on every board of the same model, then use deploy-rs to apply the final
host configuration from this flake.

The bootstrap contains only what deployment requires:

- the board-specific bootloader, kernel, modules, firmware, and device tree;
- DHCP networking;
- an on-console network banner showing each interface's IP and MAC address;
- key-only SSH access for the `nixos` user;
- local-console recovery using the temporary `nixos` / `nixos` login;
- passwordless sudo for system activation; and
- Nix with flakes enabled for a deploy-rs remote build.

It does not contain Technitium, the common role configuration, machine secrets,
or a final hostname. SSH host keys and other persistent machine identity are
generated independently when each board first boots.

## Rock Pi 4B+

The `rockpi-4b` bootstrap configuration uses Armbian's board-tested Rockchip64
kernel, `rk3399-rock-pi-4b-plus.dtb`, and Rock Pi 4B+ U-Boot assets. The assets
are pinned by URL and SHA-256. The current pins are Armbian 26.5.1, U-Boot
2022.07, and kernel 6.18.35.

Build it locally with an AArch64 Linux builder:

```console
nix build .#rockpi-4b-bootstrap-image
```

The **SBC Rock Pi 4B+ image** GitHub Actions workflow builds the same flake
output on a native ARM64 runner through the shared SBC image builder. Its
`sbc-rockpi-4b` artifact contains:

- `nixos-rockpi-4b-bootstrap.img.zst`
- `nixos-rockpi-4b-bootstrap.img.zst.sha256`

The artifact is retained for 14 days. It is not encrypted because the bootstrap
contains no secrets; its authorized SSH keys are public keys.

## Rock 5A

The `rock-5a` bootstrap configuration follows Armbian's Rock 5A board definition:
RK3588S, `rk3588s-rock-5a.dtb`, GPT, and the board-specific U-Boot assets. It
shares the pinned Armbian 26.5.1 / Linux 6.18.35 Rockchip64 kernel with the Rock
Pi 4B+ image. Board-specific assets remain under each model directory; the
shared kernel packaging lives in `lib/sbc/armbian-rockchip64.nix`.

Build it locally with an AArch64 Linux builder:

```console
nix build .#rock-5a-bootstrap-image
```

The **SBC Rock 5A image** workflow publishes an `sbc-rock-5a` artifact containing:

- `nixos-rock-5a-bootstrap.img.zst`
- `nixos-rock-5a-bootstrap.img.zst.sha256`

## Orange Pi 6 Plus

The `orange-pi-6-plus` bootstrap is an ACPI/UEFI image. Unlike the Rockchip
boards, it contains no U-Boot or device tree. The board's SPI firmware supplies
UEFI and ACPI; the disk image supplies a GPT EFI System Partition containing
the standard AArch64 fallback loader at `EFI/BOOT/BOOTAA64.EFI`.

The kernel uses Armbian's Linux 6.18 CIX P1 config and patch series, pinned from
the `armbian/build` revision used by this flake. Armbian does not currently
publish a standalone `linux-image-current-cix-p1` package in its APT pool, so
the image builds the kernel from those reproducible source assets rather than
extracting it from a large community image. The bootstrap deliberately omits
the proprietary GPU/NPU/VPU userspace stack. The unstable `aipu` NPU module is
blacklisted, as it is in Armbian's current platform definition.

Build it locally with an AArch64 Linux builder:

```console
nix build .#orange-pi-6-plus-bootstrap-image
```

The **SBC Orange Pi 6 Plus image** workflow publishes an
`sbc-orange-pi-6-plus` artifact containing:

- `nixos-orange-pi-6-plus-bootstrap.img.zst`
- `nixos-orange-pi-6-plus-bootstrap.img.zst.sha256`

Before booting, install a current Orange Pi GeneralBIOS in the board's SPI
flash, disable Secure Boot, and select `ACPI` under **CIX System Manager →
System Table Selection**. The image does not update or overwrite SPI firmware.

## Flash

Verify the checksum, identify the whole eMMC device, and stream the compressed
image directly to it:

```console
IMAGE=nixos-orange-pi-6-plus-bootstrap.img.zst
sha256sum --check "$IMAGE.sha256"
lsblk
zstd -dc "$IMAGE" \
  | sudo dd of=/dev/mmcblkX bs=4M status=progress conv=fsync
sync
```

Replace `/dev/mmcblkX` with the whole eMMC device, not a partition. Selecting
the wrong device destroys its existing contents.

The Rock Pi 4B+ and Rock 5A images leave the first 16 MiB unpartitioned. They
write Armbian's `idbloader.img` at sector 64 and `u-boot.itb` at sector 16384,
outside the first filesystem partition. The Rock 5A image converts the
partition table to GPT as specified by Armbian's board definition.

The Orange Pi 6 Plus image instead starts with a GPT EFI System Partition and
can be flashed to microSD, USB storage, or NVMe. Its firmware discovers
`BOOTAA64.EFI` directly; there are no raw bootloader sectors.

## First deployment

Connect Ethernet and boot the board. Before the login prompt, the serial and
display consoles show every non-loopback interface's acquired IP addresses and
MAC address. Use the displayed IPv4 address to verify bootstrap access:

```console
ssh nixos@<dhcp-address>
```

SSH access requires the private key matching one of the public deployment keys
embedded in the image; password login over SSH is disabled. For local recovery
on the serial or display console, the bootstrap login is `nixos` with password
`nixos`. This intentionally public password exists only in the generic
bootstrap configuration. The first deploy-rs activation replaces it with the
final password hash from `secrets/crypt.toml`.

From this flake checkout, override the deployment hostname for the first run:

```console
deploy --hostname <dhcp-address> .#rockpi-dns-1
```

For the second board, use its own DHCP address and target:

```console
deploy --hostname <dhcp-address> .#rockpi-dns-2
```

The final configurations retain the Rock Pi hardware module and add their
hostname, common system configuration, and Technitium role. Subsequent updates
can use their final resolvable names:

```console
deploy .#rockpi-dns-1
deploy .#rockpi-dns-2
```

Because every freshly flashed board initially uses the hostname
`rockpi-4b-bootstrap`, identify them by DHCP address or MAC address. Booting and
deploying them one at a time avoids ambiguity.

## Adding another SBC model

Follow the same separation for each board family:

1. Pin the model's bootloader, kernel, firmware, and device tree assets.
2. Put runtime hardware settings in a shared hardware module imported by every
   final role for that model.
3. Create one bootstrap configuration that combines the hardware module,
   `modules/nixos/sbc-bootstrap`, and the model's image layout.
4. Export one `<model>-bootstrap-image` flake package and add it to the image
   workflow.

Raspberry Pi 4 will need its own hardware and image-layout module, but it can
share the same deployment bootstrap base and role-first workflow.
