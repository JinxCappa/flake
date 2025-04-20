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

  boot = {
    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };
  };

  time.timeZone = "US/Eastern";
  i18n.defaultLocale = "en_US.UTF-8";
  networking.hostName = lib.mkForce toml.zitadel.hostname;
  networking.domain = toml.domain;
  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users = {
    mutableUsers = false;
    users = {
      nixos = {
        isNormalUser = true;
        extraGroups = [ "wheel" "docker" ];
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

  programs.zsh.enable = true;

  system.stateVersion = "24.11";

  environment.systemPackages = with pkgs; [
    htop
  ];

  deploy = {
    address = toml.zitadel.address;
    remoteBuild = true;
    user = "nixos";
  };

  nix = {
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
    settings = {
      substituters = toml.nix.substituters;
      trusted-public-keys = toml.nix.trusted-public-keys;
    };
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  environment.etc."nixos/docker-compose.yaml".source = files/crypt/docker-compose.yaml;

  systemd.services = {
    "docker-init" = {
      enable = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutSec = 600;
      };
      after = [
        "docker.service"
      ];
      requires = [
        "docker.service"
      ];
      preStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/docker-compose.yaml down";
      script = "${pkgs.docker}/bin/docker compose -f /etc/nixos/docker-compose.yaml up -d";
      postStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/docker-compose.yaml down";
      wantedBy = ["multi-user.target"];
    };
  };

  services = {
    cron = {
      enable = true;
      systemCronJobs = [
        "@daily nixos ${pkgs.docker}/bin/docker exec acme.sh --cron"
      ];
    };
    incron = {
      enable = true;
      systab = ''
        /etc/acme/certs/${toml.zitadel.hostname}.${toml.domain}_ecc/fullchain.cer IN_CLOSE_WRITE ${pkgs.docker}/bin/docker restart zitadel
      '';
    };
  };
}