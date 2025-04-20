{
  lib,
  pkgs,
}:

# Board-specific U-Boot plus the shared Armbian Rockchip64 kernel.
let
  kernelAssets = import ../../../lib/sbc/armbian-rockchip64.nix { inherit lib pkgs; };
  armbianRelease = kernelAssets.release;

  armbianUbootDeb = pkgs.fetchurl {
    url = "https://apt.armbian.com/pool/main/l/linux-u-boot-rock-5a-current/linux-u-boot-rock-5a-current_${armbianRelease}_arm64__2017.09-S39cd-P1ff0-H40c4-Vc6b1-Bd0d2-R448a.deb";
    hash = "sha256-iPHq8MkTSceWr4p9AKT6hUlNF0CNhutdtlXMsDsonYg=";
  };

  uboot =
    pkgs.runCommand "armbian-rock-5a-uboot-${armbianRelease}"
      {
        nativeBuildInputs = [ pkgs.dpkg ];
      }
      ''
        dpkg-deb --extract ${armbianUbootDeb} ./root
        src=./root/usr/lib/linux-u-boot-current-rock-5a

        install -Dm0644 "$src/idbloader.img" "$out/idbloader.img"
        install -Dm0644 "$src/u-boot.itb" "$out/u-boot.itb"
      '';
in
kernelAssets
// {
  inherit uboot;
  ubootVersion = "2017.09";
}
