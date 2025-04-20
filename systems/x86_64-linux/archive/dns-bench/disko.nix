{ lib, ... }:
{
  disko.devices.disk.main = {
    # /dev/vda is the common VirtIO system disk. Confirm this with `lsblk`
    # in the provider's rescue image and change it before installation when
    # the provider uses /dev/sda, NVMe, or a stable /dev/disk/by-id path.
    device = lib.mkDefault "/dev/vda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          name = "boot";
          size = "1M";
          type = "EF02";
        };
        esp = {
          name = "ESP";
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
