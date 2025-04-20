{
  # The library supplied by the NixOS module evaluator, extended by this flake.
  lib,
  # The nixpkgs package set with this flake's overlays applied.
  pkgs,
  # Flake inputs supplied by the flake's system builder.
  inputs,
  # The evaluated NixOS configuration.
  config,
  ...
}:
let
  toml = lib.importTOML ../../../secrets/crypt.toml;
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./files/crypt/docker.nix
  ];

  common.enable = true;

  networking = {
    useDHCP = false;
    defaultGateway = {
      address = toml.${config.networking.hostName}.gateway;
      interface = "ens3";
    };
    nameservers = [
      "46.38.225.230"
      "46.38.252.230"
    ];
    interfaces.ens3 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = toml.${config.networking.hostName}.address;
          prefixLength = 22;
        }
      ];
    };
  };

  sops = {
    useSystemdActivation = true;
    defaultSopsFile = ./files/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.omni_dex_admin_email = { };
    secrets.omni_dex_admin_hash = { };
    secrets.omni_asc = { };
  };

  services = {
    resolved.enable = true;
  };

  deploy = {
    address = toml.${config.networking.hostName}.address;
    remoteBuild = true;
    user = "nixos";
  };

  services.qemuGuest.enable = true;

  security.pki.certificateFiles = [
    ./files/crypt/ca.crt
    ./files/crypt/rootca.crt
  ];

  environment.etc."/nixos/unifi/init-mongo.sh".source = ./files/crypt/init-mongo.sh;

}
