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

  system.nixos.tags = lib.mkForce [ "sbc" ];

  networking.hostName = "rock-5a-bootstrap";

  # Bootstrap over wired Ethernet; final role configurations restore firmware.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  # Preserve Armbian's GPT layout and leave room for Rockchip's raw boot assets.
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
      # sd-image.nix creates an MBR image. Convert it to the GPT layout used by
      # Armbian's Rock 5A images, retaining partition 2 as the boot partition.
      truncate -s +1M "$img"
      ${pkgs.gptfdisk}/bin/sgdisk --mbrtogpt "$img"
      ${pkgs.gptfdisk}/bin/sgdisk \
        --disk-guid=7e6c9f11-3a76-4e5c-bf0e-57a501000000 \
        --partition-guid=1:7e6c9f11-3a76-4e5c-bf0e-57a501000001 \
        --partition-guid=2:7e6c9f11-3a76-4e5c-bf0e-57a501000002 \
        "$img"
      ${pkgs.gptfdisk}/bin/sgdisk --attributes=2:set:2 "$img"
      ${pkgs.gptfdisk}/bin/sgdisk --verify "$img"

      dd if=${assets.uboot}/idbloader.img of="$img" bs=512 seek=64 conv=notrunc
      dd if=${assets.uboot}/u-boot.itb of="$img" bs=512 seek=16384 conv=notrunc
    '';
  };

  image.baseName = "nixos-rock-5a-bootstrap";
}
