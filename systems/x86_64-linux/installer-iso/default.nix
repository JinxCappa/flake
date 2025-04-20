{ modulesPath, ... }:
# Bootable installer ISO for nixos-anywhere.
#
# Build:
#   nix build .#installer-iso
#   # from non-Linux hosts, configure an x86_64-linux builder first
#   # -> result/iso/*.iso   (also: .#nixosConfigurations.installer-iso.config.system.build.isoImage)
#
# Then flash with `dd`/Ventoy, boot the target, find its DHCP address, and:
#   nix run github:numtide/nixos-anywhere -- \
#     --flake .#<host> nixos@<target-ip>
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../_installer-base.nix
  ];

  image.fileName = "nixos-anywhere-installer.iso";
  # Faster boot: ISO doesn't need a compressed squashfs to be small here.
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";
}
