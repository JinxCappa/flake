{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  inputs,

  # Additional metadata is provided by Snowfall Lib.
  system, # The system architecture for this host (eg. `x86_64-linux`).
  target, # The Snowfall Lib target for this system (eg. `x86_64-iso`).
  format, # A normalized name for the system target (eg. `iso`).
  virtual, # A boolean to determine whether this system is a virtual target using nixos-generators.
  systems, # An attribute map of your defined hosts.

  # All other arguments come from the system system.
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
    interfaces = {
      ens3 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = toml.${config.networking.hostName}.address;
            prefixLength = 22;
          }
        ];
      };
      ens4.ipv4.addresses = [
        {
          address = "10.10.0.2";
          prefixLength = 24;
        }
      ];
    };
    firewall.enable = true;
  };

  sops = {
    defaultSopsFile = ./files/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  services.qemuGuest.enable = true;

  deploy = {
    address = toml.${config.networking.hostName}.address;
    remoteBuild = true;
    user = "nixos";
  };

}
