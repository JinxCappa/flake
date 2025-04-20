{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.common;
  toml = lib.importTOML ../../../secrets/crypt.toml;
  ageKeyPath = "/root/.config/sops/age/keys.txt";
  ageKeyDir = "/root/.config/sops/age";
in
{
  options.common.enable = lib.mkEnableOption "common system configuration";

  config = lib.mkIf cfg.enable {
    boot = {
      loader.grub = {
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
    };

    time.timeZone = "US/Eastern";
    i18n.defaultLocale = "en_US.UTF-8";
    networking.domain = toml.domain;
    networking.firewall.enable = lib.mkDefault false;

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
          extraGroups = [ "wheel" ];
          hashedPassword = toml.password or null;
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

    security.pki.certificateFiles = [
      ./certificates/root-ca.crt
    ];

    programs.zsh.enable = true;

    system.stateVersion = lib.mkDefault "26.11";

    environment.systemPackages = with pkgs; [
      htop
      age
      ssh-to-age
    ];

    nix = {
      nixPath = [ "nixpkgs=flake:nixpkgs" ];
      gc = {
        automatic = true;
        dates = "daily";
        persistent = true;
        randomizedDelaySec = "45min";
        options = "--delete-old";
      };
      settings = {
        substituters = toml.nix.substituters;
        trusted-public-keys = toml.nix.trusted-public-keys;
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        download-buffer-size = 134217728; # 128MB
      };
    };

    # Generate age key for root user if it doesn't exist
    system.activationScripts.generateRootAgeKey.text = ''
      if [ ! -f "${ageKeyPath}" ]; then
        echo "Generating age key for root at ${ageKeyPath}..."
        mkdir -p "${ageKeyDir}"
        chmod 700 "${ageKeyDir}"
        ${pkgs.age}/bin/age-keygen -o "${ageKeyPath}" 2>/dev/null
        chmod 600 "${ageKeyPath}"
        echo "Age key generated. Add this public key to .sops.yaml:"
        ${pkgs.age}/bin/age-keygen -y "${ageKeyPath}"
      fi
    '';

    # Configure sops-nix to use the generated age key
    sops = {
      age.keyFile = ageKeyPath;
    }
    // lib.optionalAttrs (pkgs ? sops-install-secrets) {
      package = lib.mkDefault pkgs.sops-install-secrets;
    };

  };
}
