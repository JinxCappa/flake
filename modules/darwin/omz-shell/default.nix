{
  config,
  lib,
  ...
}:
with lib;
with lib.aulogix; let
  cfg = config.omz-shell;
in {
  options.omz-shell = {
    enable = mkEnableOption "Enable oh-my-zsh shell";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      zsh
      git
    ];

    home-manager.users = {
      nixos = {
        packages = with pkgs; [
          oh-my-zsh
        ];
        home = "/nix/var/nix/profiles/per-user/nixos/home-manager";
        homeFile = "home.nix";
        stateVersion = "24.11";
        homeState = {
          programs.zsh = {
            enable = true;
            enableOhMyZsh = true;
            theme = "agnoster";
          };
        };
      };
    };
  };
}