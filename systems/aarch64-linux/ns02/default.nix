{ lib, pkgs, config, ... }:
let
  toml = lib.importTOML ../../../secrets/crypt.toml; 
in
{
  imports = [ ../rockpi-4b/hardware.nix ];

  common.enable = true;

  networking.useDHCP = true;
  networking.firewall.enable = lib.mkForce true;

  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;
  };

  services.chrony = {
    enable = true;
    servers = [ "time.cloudflare.com" "time.google.com" ];
  };

  deploy = {
    address = toml.${config.networking.hostName}.address;
    remoteBuild = true;
    user = "nixos";
  }; 
}
