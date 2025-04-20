{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
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
    ./files/crypt/docker-compose.nix
  ];

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.initrd.kernelModules = [
    ## Which kernel module / driver for the network interface?
    # lspci -v | grep -iA8 'network\|ethernet'
    # nix run nixpkgs#lshw -- -C network | grep -Poh 'driver=[[:alnum:]]+'
    # "igb" # Intel Gigabit
    # "e1000e"
    # "igc"
    # "r8169"

    # # For debugging installation in vms
    "virtio_pci"
    "virtio_net"
  ];

  boot.kernelParams = [
    #   # See <https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt> for docs on this
    #   # ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>:<dns0-ip>:<dns1-ip>:<ntp0-ip>
    #   # The server ip refers to the NFS server -- we don't need it.
    #   # "ip=${ipv4.address}::${ipv4.gateway}:${ipv4.netmask}:${hostName}-initrd:${networkInterface}:off:1.1.1.1"
    ## initrd luks_remote_unlock
    # "ip=192.168.1.35::192.168.1.1:255.255.255.0:my-server-initrd:eth0:none"
    "ip=dhcp"
  ];

  boot.initrd = {
    secrets = {
      "/etc/secrets/initrd/ssh_host_ed25519_key" = ../../../secrets/ssh_host_ed25519_key;
    };
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = config.users.users.nixos.openssh.authorizedKeys.keys;
        hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
        shell = "/bin/cryptsetup-askpass";
        extraConfig = ''
          PermitRootLogin prohibit-password
          PasswordAuthentication no
          KbdInteractiveAuthentication no
        '';
      };
    };
  };

  time.timeZone = "US/Eastern";
  i18n.defaultLocale = "en_US.UTF-8";
  networking.domain = toml.domain;
  # networking.firewall.enable = false;

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
        extraGroups = [
          "wheel"
          "docker"
        ];
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
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  deploy = {
    address = toml.ui.address;
    remoteBuild = true;
    user = "nixos";
  };

  programs.zsh.enable = true;

  nix = {
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
    settings = {
      substituters = toml.nix.substituters;
      trusted-public-keys = toml.nix.trusted-public-keys;
    };
  };

  environment.etc."secrets/initrd/ssh_host_ed25519_key".source =
    ../../../secrets/ssh_host_ed25519_key;
  environment.etc."secrets/initrd/ssh_host_ed25519_key".mode = "0600";
  environment.systemPackages = with pkgs; [
    htop
  ];

  system.stateVersion = "25.05";

  environment.etc."/nixos/caddy/Caddyfile".source = ./files/crypt/Caddyfile;
  environment.etc."/nixos/unifi/init-mongo.sh".source = ./files/crypt/init-mongo.sh;
}
