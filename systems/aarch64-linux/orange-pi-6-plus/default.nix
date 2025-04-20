{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:

let
  assets = import ./assets.nix { inherit config pkgs; };
in
{
  imports = [
    ./hardware.nix
    ../../../modules/nixos/sbc-bootstrap
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  sbcBootstrap.enable = true;

  system.nixos.tags = lib.mkForce [ "sbc" ];

  networking.hostName = "orange-pi-6-plus-bootstrap";

  # The wired NIC and storage do not require the old proprietary BSP bundle.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  sdImage = {
    compressImage = true;
    firmwarePartitionOffset = 1;
    firmwareSize = 512;
    firmwarePartitionName = "NIXOS_EFI";
    populateFirmwareCommands = ''
      mkdir -p firmware/EFI/BOOT firmware/grub
      cp ${assets.grubEfi} firmware/EFI/BOOT/BOOTAA64.EFI
      cp ${assets.grubConfig} firmware/grub/grub.cfg
      cp ${config.system.build.toplevel}/kernel firmware/kernel
      cp ${config.system.build.toplevel}/initrd firmware/initrd
    '';
    populateRootCommands = "";
    postBuildCommands = ''
      # UEFI/ACPI firmware expects a GPT disk with a real EFI System Partition.
      truncate -s +1M "$img"
      ${pkgs.gptfdisk}/bin/sgdisk --mbrtogpt "$img"
      ${pkgs.gptfdisk}/bin/sgdisk \
        --typecode=1:ef00 \
        --change-name=1:NixOS-EFI \
        --change-name=2:NixOS \
        "$img"
      ${pkgs.gptfdisk}/bin/sgdisk --verify "$img"
    '';
  };

  image.baseName = "nixos-orange-pi-6-plus-bootstrap";
}
