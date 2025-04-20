{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  ...
}:
let
  toml = lib.importTOML ../../../secrets/crypt.toml;
in
{
  system.stateVersion = 5;
  system.primaryUser = "jinx";

  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "backup";

  nix.settings.trusted-users = [ "jinx" ];

  nix.settings.substituters = toml.nix.substituters;

  nix.settings.trusted-public-keys = toml.nix.trusted-public-keys;

  # Configure remote Linux builder for x86_64-linux builds
  # nix.buildMachines = [
  #   {
  #     hostName = "192.168.10.176";
  #     system = "aarch64-linux";
  #     maxJobs = 4;
  #     speedFactor = 1;
  #     supportedFeatures = [
  #       "nixos-test"
  #       "benchmark"
  #       "big-parallel"
  #       "kvm"
  #     ];
  #     mandatoryFeatures = [ ];
  #     sshUser = "dietpi";
  #     sshKey = "/Users/jinx/.ssh/id_ed25519"; # Update this to your SSH key path
  #   }
  # ];

  nix.distributedBuilds = true;
  # Optional: fall back to building locally if remote is unavailable
  nix.extraOptions = ''
    builders-use-substitutes = true
    experimental-features = nix-command flakes
  '';

  nix-homebrew.enableRosetta = false;

  # nix.linux-builder = {
  #   enable = true;
  #   systems = [ "x86_64-linux" "aarch64-linux" ];
  #   ephemeral = true;
  #   maxJobs = 4;
  #   config = {
  #     virtualisation = {
  #       darwin-builder = {
  #         diskSize = 40 * 1024;
  #         memorySize = 8 * 1024;
  #       };
  #       # rosetta.enable = true;
  #       cores = 4;
  #     };
  #   };
  # };

  environment.systemPackages = with pkgs; [
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
    ripgrep
    compose2nix
    gh
    gnupg
    devenv
    docker
    deploy-rs
    tokei
    cloc
    markdownlint-cli2
    bun
    uv
    coreutils
    nodejs_24
    tree
    nvfetcher
    cloudflared
    pnpm
    yarn
    go
    yq-go
    nil
    gradle_9
  ];

  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
    };

    brews = [
      "docker-credential-helper"
      "cmake"
      "libb2"
      "zstd"
      "bzip2"
      "libarchive"
      "deno"
      "cargo-binstall"
      "cargo-nextest"
      "supabase"
      "mosh"
      "moshi-hook"
    ];

    casks = [
      "mitmproxy"
    ];

    taps = [
      "homebrew/homebrew-core"
      "homebrew/homebrew-cask"
      "supabase/homebrew-tap"
      "rjyo/moshi"
    ];

    masApps = {
    };
  };
}
