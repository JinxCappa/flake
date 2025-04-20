{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cix = import ../../../lib/sbc/armbian-cix-p1.nix {
    armbianBuild = inputs.armbian-build;
    inherit lib pkgs;
  };
in
{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  boot = {
    kernelPackages = lib.mkForce cix.kernelPackages;
    kernelParams = [
      "console=ttyAMA2,115200n8"
      "console=tty0"
      "earlycon=pl011,0x040d0000"
      "efi=noruntime"
      "clk_ignore_unused"
      "nowatchdog"
      "watchdog_dev.handle_boot_enabled=0"
    ];
    blacklistedKernelModules = [
      "aipu"
      "armchina_npu"
    ];
    initrd.availableKernelModules = lib.mkForce [
      "nvme"
      "sd_mod"
      "uas"
      "usb_storage"
    ];
    loader = {
      generic-extlinux-compatible.enable = lib.mkForce false;
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        efiInstallAsRemovable = true;
        configurationLimit = 3;
      };
      efi = {
        canTouchEfiVariables = false;
        efiSysMountPoint = "/boot/firmware";
      };
    };
  };

  # The generic SD image enables drivers for every supported ARM board. This
  # image only needs the CIX storage stack selected above.
  hardware.enableAllHardware = lib.mkForce false;

  # The CIX P1 firmware supplies ACPI tables; no device tree is installed.
  hardware.deviceTree.enable = lib.mkForce false;

  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/NIXOS_SD";
    fsType = lib.mkDefault "ext4";
  };

  fileSystems."/boot/firmware".options = lib.mkForce [ "umask=0077" ];
}
