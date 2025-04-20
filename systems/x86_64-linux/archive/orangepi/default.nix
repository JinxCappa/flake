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
    inputs.orangepi6plus.nixosModules.default
  ];

  # Hardware configuration (filesystems) is local, kernel/drivers come from orangepi6plus module

  time.timeZone = "US/Eastern";
  i18n.defaultLocale = "en_US.UTF-8";
  networking.firewall.enable = false;

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
      orangepi = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh = {
          authorizedKeys = {
            keys = toml.ssh-keys;
          };
        };
        hashedPassword = toml.password;
        shell = pkgs.zsh;       
      };
    };
  };

  security.sudo.extraRules = [
    { 
      users = [ "orangepi" ];
      commands = [ { command = "ALL"; options = ["NOPASSWD"]; } ];
    }
  ];

  deploy = {
    address = toml.orangepi.address;
    remoteBuild = true;
    user = "orangepi";
    sshUser = "orangepi";
  };

  programs.zsh.enable = true;

  nix = {
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
    settings = {
      substituters = toml.nix.substituters;
      trusted-public-keys = toml.nix.trusted-public-keys;
    };
  };

  environment.systemPackages = with pkgs; [
    htop
  ];

  system.stateVersion = "26.05";
}