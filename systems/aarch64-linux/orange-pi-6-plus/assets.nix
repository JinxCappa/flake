{
  config,
  pkgs,
}:

let
  grub = pkgs.grub2.override {
    efiSupport = true;
  };
in
{
  grubEfi =
    pkgs.runCommand "orange-pi-6-plus-grubaa64.efi"
      {
        nativeBuildInputs = [ grub ];
      }
      ''
        grub-mkimage \
          -O arm64-efi \
          -o "$out" \
          -p /grub \
          part_gpt part_msdos fat ext2 normal boot linux \
          configfile chain efifwsetup efi_gop \
          search search_label search_fs_uuid search_fs_file \
          gfxterm test all_video echo
      '';

  grubConfig = pkgs.writeText "orange-pi-6-plus-grub.cfg" ''
    set default=0
    set timeout=3

    menuentry "NixOS - Orange Pi 6 Plus bootstrap" {
      linux /kernel init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}
      initrd /initrd
    }
  '';
}
