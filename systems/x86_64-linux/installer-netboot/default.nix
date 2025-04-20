{ modulesPath, ... }:
# PXE / netboot assets for nixos-anywhere.
#
# Build the three artifacts your boot server serves:
#   nix build .#installer-netboot            # -> result: kernel + initrd + ipxe script symlinks
#   # from non-Linux hosts, configure an x86_64-linux builder first
#   # individually:
#   nix build .#nixosConfigurations.installer-netboot.config.system.build.kernel
#   nix build .#nixosConfigurations.installer-netboot.config.system.build.netbootRamdisk
#   nix build .#nixosConfigurations.installer-netboot.config.system.build.netbootIpxeScript
#
# Point your DHCP/TFTP/iPXE at the generated `netboot.ipxe`, boot the target,
# then run nixos-anywhere against its DHCP address (nixos@<ip>).
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ../_installer-base.nix
  ];
}
