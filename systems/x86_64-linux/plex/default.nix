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
  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = toml.ssh-keys;

  environment.systemPackages = with pkgs; [
    htop
  ];

  nix.nixPath = [
    "nixpkgs=flake:nixpkgs"
  ];

  nix.settings.substituters = toml.nix.substituters;

  nix.settings.trusted-public-keys = toml.nix.trusted-public-keys;

  deploy = {
    address = toml.plex.address;
    remoteBuild = true;
    sshUser = "root";
  };

  system.stateVersion = "24.11";

  networking.interfaces.eno1.useDHCP = false;
  networking.dhcpcd.wait = "ipv4";
  networking.interfaces.enp1s0.mtu = 9000;

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  environment.etc."nixos/plex/docker-compose.yaml".source = ./files/docker-compose.yaml;

  systemd.services = {
    "plex-server" = {
      serviceConfig = {
        Type = "oneshot";
        TimeoutSec = 600;
        Restart = "on-failure";
        RestartMaxDelaySec = "1m";
        RestartSec = "1s";
        RestartSteps = 4;
        RemainAfterExit = true;
        ExecStart = "${pkgs.docker}/bin/docker compose -f /etc/nixos/plex/docker-compose.yaml up -d";
        ExecStop = "${pkgs.docker}/bin/docker compose -f /etc/nixos/plex/docker-compose.yaml down";

      };
      after = [ 
        "docker.service"
        "network-online.target"  
      ];
      requires = [ 
        "docker.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];
    };
  };

  services.cadvisor = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9999;
    extraOptions = [
      "--docker_only=true"
    ];
  };
}