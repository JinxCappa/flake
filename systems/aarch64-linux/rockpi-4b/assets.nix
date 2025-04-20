{
  lib,
  pkgs,
}:

# Board-specific U-Boot plus the shared Armbian Rockchip64 kernel.
let
  kernelAssets = import ../../../lib/sbc/armbian-rockchip64.nix { inherit lib pkgs; };
  armbianRelease = kernelAssets.release;

  armbianUbootDeb = pkgs.fetchurl {
    url = "https://apt.armbian.com/pool/main/l/linux-u-boot-rockpi-4bplus-current/linux-u-boot-rockpi-4bplus-current_${armbianRelease}_arm64__2022.07-Se092-P621f-Hd9fb-V5677-Bd0d2-R448a.deb";
    hash = "sha256-3x0ZE3EVJ8EiOkEkqQj/1fZHH983l86KDvFelM+5OA0=";
  };

  uboot =
    pkgs.runCommand "armbian-rockpi-4bplus-uboot-${armbianRelease}"
      {
        nativeBuildInputs = [ pkgs.dpkg ];
      }
      ''
        dpkg-deb --extract ${armbianUbootDeb} ./root
        src=./root/usr/lib/linux-u-boot-current-rockpi-4bplus

        install -Dm0644 "$src/idbloader.img" "$out/idbloader.img"
        install -Dm0644 "$src/u-boot.itb" "$out/u-boot.itb"
      '';

in
kernelAssets
// {
  inherit uboot;
  ubootVersion = "2022.07";
}
