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
    ./compute-devbox.nix
    ./storage-devbox.nix
  ];

  _module.args.toml = toml;

  common.enable = true;
  computeDevbox.enable = true;
  storageDevbox.enable = true;

  users.users.nixos.initialHashedPassword = toml.password;

  deploy = {
    address = toml.${config.networking.hostName}.address;
    remoteBuild = true;
    user = "nixos";
    sshUser = "compute";
  };
}
