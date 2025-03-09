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
    home, # The home architecture for this host (eg. `x86_64-linux`).
    target, # The Snowfall Lib target for this home (eg. `x86_64-home`).
    format, # A normalized name for the home target (eg. `home`).
    virtual, # A boolean to determine whether this home is a virtual target using nixos-generators.
    host, # The host name for this home.

    # All other arguments come from the home home.
    config,
    ...
}:
{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "jinx";
  home.homeDirectory = "/Users/jinx";

  home.stateVersion = "24.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    oh-my-zsh
    starship
    krew
    git
    htop
    direnv
    ssh-to-age
    sops
    age
    cilium-cli
    kubernetes-helm
    kubectl
    fd
    broot
    nixos-anywhere
    deploy-rs
    devbox
    ripgrep
    compose2nix
  ];

  home.file.".oh-my-zsh/custom/custom.zsh".text = ''
    export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt
  '';

  programs.zsh = {
    enable = true;
    autocd = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "starship"
      ];
      theme = "lukerandall";
      extraConfig = ''
        zstyle ':omz:update' mode reminder
        eval "$(starship init zsh)"
        eval "$(devbox global shellenv)"
        export PATH="$HOME/.krew/bin:$PATH"
        export ZSH_CUSTOM=~/.oh-my-zsh/custom
      '';
    };
  };
}