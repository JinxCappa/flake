{
  config,
  lib,
  ...
}:

let
  # Public deployment keys only. Hardware bootstrap images do not import
  # secrets/crypt.toml or any role-specific configuration.
  sshKeys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDkNR9hLm+0AJXEtH7JFjNOdG3TxCyVLYrV1fbNWCWO47RuBHRT7rq3fGGsiab6HtXfQzRA1VMmWe/7Kw6VWq4n7b8kfH8q/oPYbYb5suw/7xVhdE4m2PVNQ3MMCnByyH/M2jpRZSu85yo7hxbhU99p3zs65ZBt6fL+A2mXyRoWgcvl3P4NacvHfG5Qx3diZlya+ly7Ve7SdLAOp8KdP44es9MQsTM6s2qNH2rwc0BKYJMEwjOHawinRCoNhFAOAasXze70ooy9ikFaZnw2uDQBpo3c2KfTGJl4x4r+cjFOWDepqhNUFqJ8Kc0IKe2KpP/KFBvI4lqssHXa2x/4+Jrp"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL297YEnIQsbYdos0I+ENisd3alAm/TpvvUwJ6lKjdGZ"
  ];
  cfg = config.sbcBootstrap;
in
{
  imports = [ ../bootstrap-console ];

  options.sbcBootstrap.enable = lib.mkEnableOption "minimal SBC deployment bootstrap";

  config = lib.mkIf cfg.enable {
    networking = {
      useDHCP = lib.mkDefault true;
      firewall.enable = true;
    };

    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    users = {
      mutableUsers = false;
      users.nixos = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        # This is an intentionally public, local-console bootstrap password.
        # Network logins remain key-only and the deployed host configuration
        # replaces it with the password hash from secrets/crypt.toml.
        password = "nixos";
        openssh.authorizedKeys.keys = sshKeys;
      };
    };

    bootstrapConsole = {
      enable = true;
      instructions = [
        "Local login: nixos / nixos (bootstrap only)"
        "SSH login:   nixos@<IPv4 address> (SSH key required)"
      ];
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

    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "nixos" ];
    };

    # Nix, SSH, sudo, and their runtime dependencies are sufficient for deploy-rs.
    environment.defaultPackages = lib.mkForce [ ];

    documentation.enable = false;
    documentation.nixos.enable = false;

    system.stateVersion = "26.05";
  };
}
