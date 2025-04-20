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
}: let
  toml = lib.importTOML ../../../secrets/crypt.toml; 
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  common.enable = true;

  networking.hostName = toml.openbao.hostname;

  sops = {
    defaultSopsFile = ./files/secrets.yaml;
    secrets."openbao-config" = {
      format = "binary";
      sopsFile = ./files/config.hcl;
      restartUnits = [ "openbao.service" ];
    };
  };

  systemd.services.openbao.serviceConfig = {
    LoadCredential = "config.hcl:${config.sops.secrets."openbao-config".path}";
  };

  deploy = {
    address = toml.openbao.address;
    remoteBuild = true;
    user = "nixos";
  };

  environment.etc."ssl/mtls/client-ca.pem" = {
    source = ./files/crypt/client-ca.pem;
    mode = "0644";
  };

  systemd.tmpfiles.rules = [
    "d /var/www/pki 0755 root root - -"
    "L+ /var/www/pki/root-ca.pem - - - - ${./files/crypt/root-ca.pem}"
  ];

  services.caddy = {
    enable = true;
    email = toml.acme-email;
    configFile = ./files/crypt/Caddyfile;
  };

  # services.openbao = {
  #   enable = true;
  #   package = pkgs.openbao-ui;
  #   configFilePath = "/run/credentials/openbao.service/config.hcl";
  # };

  services.vault = {
    enable = true;
    extraSettingsPaths = [ "/run/credentials/openbao.service/config.hcl" ];
  };
}