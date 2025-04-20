{
  lib,
  pkgs,
  ...
}:

let
  assets = import ./assets.nix { inherit lib pkgs; };
in
{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  boot = {
    kernelPackages = lib.mkForce assets.kernelPackages;
    kernelParams = [
      "console=ttyS2,1500000n8"
      "console=tty0"
    ];
    initrd.availableKernelModules = lib.mkForce [
      "mmc_block"
      "sdhci"
      "sdhci_of_dwcmshc"
      "dw_mmc"
      "dw_mmc_rockchip"
    ];
    loader = {
      grub.enable = lib.mkForce false;
      generic-extlinux-compatible.enable = true;
    };
  };

  hardware = {
    deviceTree.name = "rockchip/rk3588s-rock-5a.dtb";
    enableRedistributableFirmware = true;
  };

  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/NIXOS_SD";
    fsType = lib.mkDefault "ext4";
  };
}
