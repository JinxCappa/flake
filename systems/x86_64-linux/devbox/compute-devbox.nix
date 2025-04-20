# compute-devbox.nix
{
  config,
  lib,
  pkgs,
  toml,
  ...
}:

let
  cfg = config.computeDevbox;

  computePython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.jsonschema
  ]);

  nixFormatter = pkgs.nixfmt;

  installPinnedTools = pkgs.writeShellScriptBin "compute-install-pinned-tools" ''
    set -euo pipefail

    rustup toolchain install 1.97.1 --profile minimal

    rustup component add \
      --toolchain 1.97.1 \
      clippy \
      rustfmt \
      llvm-tools-preview

    rustup target add \
      --toolchain 1.97.1 \
      x86_64-unknown-linux-musl

    rustup default 1.97.1

    cargo +1.97.1 install \
      cargo-deny \
      --version 0.20.2 \
      --locked

    echo "Compute development tools installed for the current account."
  '';
in
{
  options.computeDevbox = {
    enable = lib.mkEnableOption "Leoron Compute development and qualification host";

    kernelPackages = lib.mkOption {
      type = lib.types.raw;
      default = pkgs.linuxPackages_6_18;
      defaultText = lib.literalExpression "pkgs.linuxPackages_6_18";
      description = "Linux 6.18 kernel package family used by Compute.";
    };

    cargoBuildJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Default Cargo build parallelism.";
    };

    nixMaxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Maximum concurrent Nix builds.";
    };

    nixCoresPerJob = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Maximum cores available to each Nix build.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isx86_64;
        message = "Leoron Compute currently requires an x86-64 Linux host.";
      }
      {
        assertion = lib.hasPrefix "6.18." config.boot.kernelPackages.kernel.version;
        message = "The Compute development host requires Linux 6.18.x.";
      }
    ];

    # This is stronger than Storage's fallback mkDefault, but an explicit
    # host-level boot.kernelPackages assignment remains authoritative.
    boot.kernelPackages = lib.mkOverride 900 cfg.kernelPackages;

    # This devbox is an Intel host. Expose IOMMU groups for the optional
    # legacy VFIO qualification lane while retaining passthrough performance.
    boot.kernelParams = [
      "intel_iommu=on"
      "iommu=pt"
    ];

    boot.kernelModules = [
      "kvm"
      "loop"
      "tun"
      "vhost"
      "vhost-net"
      "vfio"
      "vfio-pci"
      "vfio-iommu-type1"
      "dm-thin-pool"
    ];

    boot.extraModprobeConfig = ''
      options kvm_intel nested=1
      options kvm_amd nested=1
    '';

    boot.kernel.sysctl = {
      "user.max_user_namespaces" = lib.mkDefault 65536;
      "user.max_mnt_namespaces" = lib.mkDefault 65536;
      "user.max_pid_namespaces" = lib.mkDefault 65536;
      "user.max_net_namespaces" = lib.mkDefault 65536;
      "user.max_uts_namespaces" = lib.mkDefault 65536;
      "user.max_ipc_namespaces" = lib.mkDefault 65536;
      "user.max_cgroup_namespaces" = lib.mkDefault 65536;
    };

    users.groups.kvm = { };

    users.users.compute = {
      isNormalUser = true;

      extraGroups = [
        "wheel"
        "kvm"
      ];

      initialHashedPassword = toml.password;
      openssh.authorizedKeys.keys = toml."ssh-keys";
      shell = pkgs.zsh;
    };

    programs.zsh.enable = true;

    # Passwordless sudo applies only to the dedicated Compute account.
    security.sudo.extraRules = [
      {
        users = [ "compute" ];

        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    nix.settings = {
      keep-outputs = lib.mkDefault true;
      keep-derivations = lib.mkDefault true;

      experimental-features = lib.mkDefault [
        "nix-command"
        "flakes"
      ];

      trusted-users = lib.mkDefault [
        "root"
        "@wheel"
      ];

      max-jobs = lib.mkDefault cfg.nixMaxJobs;
      cores = lib.mkDefault cfg.nixCoresPerJob;
      auto-optimise-store = lib.mkDefault true;
    };

    # Sealed qualification inputs may be unreferenced store paths. Do not let
    # an automatic collection race an active Compute evidence run. Storage can
    # retain its own GC policy whenever this module is disabled.
    nix.gc.automatic = lib.mkForce false;
    system.autoUpgrade.enable = lib.mkDefault false;

    networking.nftables.enable = lib.mkDefault true;

    services.openssh = {
      enable = lib.mkDefault true;
      openFirewall = lib.mkDefault true;

      settings = {
        PermitRootLogin = lib.mkDefault "prohibit-password";
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = lib.mkDefault false;
      };
    };

    services.timesyncd.enable = lib.mkDefault true;
    services.fstrim.enable = lib.mkDefault true;

    environment.extraInit = ''
      export PATH="$HOME/.cargo/bin:$PATH"
    '';

    environment.variables = {
      CARGO_BUILD_JOBS = lib.mkDefault (toString cfg.cargoBuildJobs);
      CARGO_INCREMENTAL = lib.mkDefault "0";
      RUSTUP_TOOLCHAIN = lib.mkDefault "1.97.1";
      RUST_BACKTRACE = lib.mkDefault "1";
    };

    environment.systemPackages =
      (with pkgs; [
        # Source, shell, and evidence utilities
        bashInteractive
        coreutils
        diffutils
        findutils
        gnugrep
        gnused
        gawk
        git
        git-lfs
        curl
        cacert
        rsync
        jq
        ripgrep
        fd
        file
        which
        tree
        patch
        gnutar
        gzip
        xz
        zstd
        acl

        # Native and static compilation
        gcc
        clang
        lld
        binutils
        pkg-config
        cmake
        gnumake
        perl
        patchelf
        libseccomp
        pkgsStatic.stdenv.cc

        # Language and repository tooling
        rustup
        llvm
        shellcheck
        nix-output-monitor
        nixFormatter
        installPinnedTools

        # Namespace, KVM, networking, storage, and topology diagnostics
        util-linux
        iproute2
        procps
        psmisc
        lsof
        strace
        lvm2
        nftables
        bridge-utils
        ethtool
        pciutils
        usbutils
        numactl
        dmidecode
        smartmontools
        nvme-cli
        hdparm
        socat
        netcat-openbsd
      ])
      ++ [
        (lib.hiPrio computePython)
      ];

    # QEMU, OVMF, SeaBIOS, OpenSSL and libtpms come from Compute's
    # content-pinned Nix expressions. swtpm is intentionally unused.
  };
}
