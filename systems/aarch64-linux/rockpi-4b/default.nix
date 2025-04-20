{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:

let
  assets = import ./assets.nix { inherit lib pkgs; };
in
{
  imports = [
    ./hardware.nix
    ../../../modules/nixos/sbc-bootstrap
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  sbcBootstrap.enable = true;

  # The upstream image module uses "sd-card", even when the image is flashed to eMMC.
  system.nixos.tags = lib.mkForce [ "sbc" ];

  networking.hostName = "rockpi-4b-bootstrap";

  # Bootstrap over the board's wired Ethernet. Final role configurations
  # restore the complete redistributable firmware set through hardware.nix.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  # Leave room for Rockchip's raw boot assets before the first partition.
  sdImage = {
    compressImage = true;
    firmwarePartitionOffset = 16;
    populateFirmwareCommands = "";
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} \
        -d ./files/boot
    '';
    postBuildCommands = ''
      dd if=${assets.uboot}/idbloader.img of="$img" bs=512 seek=64 conv=notrunc
      dd if=${assets.uboot}/u-boot.itb of="$img" bs=512 seek=16384 conv=notrunc
    '';
  };

  image.baseName = "nixos-rockpi-4b-bootstrap";
}
