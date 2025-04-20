{ lib, pkgs, ... }:
# Shared base for the nixos-anywhere installer images (ISO + netboot/PXE).
#
# This is intentionally a plain `.nix` FILE (not a directory) so snowfall's
# host discovery ignores it — only `installer-iso/` and `installer-netboot/`
# become `nixosConfigurations`.
#
# Goal: the bare minimum a machine needs so `nixos-anywhere` can SSH in as the
# nixos user over DHCP, escalate with sudo, and take over the disk. The common
# module is left disabled (no disko / sops / grub assumptions) — an installer
# owns none of that.
let
  sshKeys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDkNR9hLm+0AJXEtH7JFjNOdG3TxCyVLYrV1fbNWCWO47RuBHRT7rq3fGGsiab6HtXfQzRA1VMmWe/7Kw6VWq4n7b8kfH8q/oPYbYb5suw/7xVhdE4m2PVNQ3MMCnByyH/M2jpRZSu85yo7hxbhU99p3zs65ZBt6fL+A2mXyRoWgcvl3P4NacvHfG5Qx3diZlya+ly7Ve7SdLAOp8KdP44es9MQsTM6s2qNH2rwc0BKYJMEwjOHawinRCoNhFAOAasXze70ooy9ikFaZnw2uDQBpo3c2KfTGJl4x4r+cjFOWDepqhNUFqJ8Kc0IKe2KpP/KFBvI4lqssHXa2x/4+Jrp"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL297YEnIQsbYdos0I+ENisd3alAm/TpvvUwJ6lKjdGZ"
  ];
in
{
  imports = [ ../../modules/nixos/bootstrap-console ];

  # Portable installers may boot on machines with unrelated ZFS pools attached.
  boot.zfs.forceImportRoot = false;

  # --- Networking: just come up on DHCP and be reachable ---
  networking = {
    useDHCP = lib.mkDefault true;
    # Predictable enough; nixos-anywhere targets by IP anyway.
    firewall.enable = false;
  };
  services.resolved.enable = true;

  # --- SSH: users and nixos-anywhere connect as nixos with a key ---
  services.openssh = {
    enable = true;
    settings = {
      # nixos-anywhere initially connects as nixos, then copies the active key
      # with sudo and reconnects internally as root while running from NixOS
      # installer media. Root has no key in the image itself.
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  services.getty = {
    autologinUser = lib.mkForce null;
    helpLine = lib.mkForce "";
  };

  # The only directly accessible account. The password is intentionally public
  # and restricted to local consoles because SSH password login is disabled.
  users.users.root.initialHashedPassword = lib.mkForce "!";
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialHashedPassword = lib.mkForce "$y$j9T$iW72nWeOLs6rqDdlECo45/$ptX.EM9.inFYVOUdYFbX9L4nzfboFy2zTB2lT.v14i7";
    openssh.authorizedKeys.keys = sshKeys;
  };
  security.sudo.wheelNeedsPassword = false;

  bootstrapConsole = {
    enable = true;
    title = "nixos-anywhere installer network:";
    instructions = [
      "Local login: nixos / nixos"
      "SSH login:   nixos@<IPv4 address> (SSH key required)"
    ];
  };

  # --- Nix: flakes for interactive debugging; nixos-anywhere builds elsewhere ---
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "nixos" ];
  };

  # --- Just enough tooling to debug a stuck install ---
  environment.systemPackages = with pkgs; [
    git
    parted
    gptfdisk
    cryptsetup
    nvme-cli
    pciutils
    usbutils
    htop
    curl
    rsync
  ];

  # Keep the image lean.
  documentation.enable = false;
  documentation.nixos.enable = false;

  system.stateVersion = "26.05";
}
