{
    # Snowfall Lib provides a customized `lib` instance with access to your flake's library
    # as well as the libraries available from your flake's inputs.
    lib,
    # An instance of `pkgs` with your overlays and packages applied is also available.
    pkgs,
    # You also have access to your flake's inputs.
    inputs,

    # Additional metadata is provided by Snowfall Lib.
    namespace, # The namespace used for your flake, defaulting to "internal" if not set.
    system, # The system architecture for this host (eg. `x86_64-linux`).
    target, # The Snowfall Lib target for this system (eg. `x86_64-iso`).
    format, # A normalized name for the system target (eg. `iso`).
    virtual, # A boolean to determine whether this system is a virtual target using nixos-generators.
    systems, # An attribute map of your defined hosts.

    # All other arguments come from the system system.
    config,
    modulesPath,
    ...
}: let
  toml = lib.importTOML ../../../secrets/crypt.toml; 
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  time.timeZone = "US/Eastern";
  i18n.defaultLocale = "en_US.UTF-8";
  networking = {
    domain = toml.domain;
    search = toml.search;
    firewall.enable = false;
  };

  services = {
    resolved.enable = true;
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };
  };

  users = {
    mutableUsers = false;
    users = {
      nixos = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh = {
          authorizedKeys = {
            keys = toml.ssh-keys;
          };
        };
        shell = pkgs.zsh;       
      };
    };
  };

  security.sudo.extraRules = [
    { 
      users = [ "nixos" ];
      commands = [ { command = "ALL"; options = ["NOPASSWD"]; } ];
    }
  ];

  system.stateVersion = "24.11";

  environment.systemPackages = with pkgs; [
    htop
  ];

  deploy = {
    address = toml.aulmon.address;
    remoteBuild = true;
    user = "nixos";
  };

  programs.zsh.enable = true;

  nix.settings.substituters = toml.nix.substituters;

  nix.settings.trusted-public-keys = toml.nix.trusted-public-keys;
}