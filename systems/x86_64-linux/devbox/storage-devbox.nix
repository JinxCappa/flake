# storage-devbox.nix
#
# Import with:
#
#   imports = [ ./storage-devbox.nix ];
#   storageDevbox.enable = true;
#
# The host configuration remains responsible for system.stateVersion, disks,
# filesystems, networking, hostname, bootloader, and SSH authorized keys.
{
  config,
  lib,
  pkgs,
  toml,
  ...
}:

let
  cfg = config.storageDevbox;

  installPinnedTools = pkgs.writeShellScriptBin "storage-install-pinned-tools" ''
    set -euo pipefail

    rustup toolchain install 1.97.1 \
      --profile minimal \
      --component clippy \
      --component rustfmt \
      --target x86_64-unknown-linux-gnu \
      --target x86_64-unknown-linux-musl \
      --target aarch64-unknown-linux-gnu \
      --target aarch64-unknown-linux-musl

    rustup default 1.97.1

    cargo +1.97.1 install \
      cargo-deny \
      --version 0.20.2 \
      --locked

    cargo +1.97.1 install \
      cargo-zigbuild \
      --version 0.20.1 \
      --locked

    echo "Pinned Rust and Cargo tools installed for the current account."
    echo "Use npx --yes markdownlint-cli2@0.23.2 for Markdown linting."
  '';
in
{
  options.storageDevbox = {
    enable = lib.mkEnableOption "Leoron Phase 1.8 Linux development host";

    kernelPackages = lib.mkOption {
      type = lib.types.raw;
      default = pkgs.linuxPackages_6_18;
      defaultText = lib.literalExpression "pkgs.linuxPackages_6_18";
      description = "Linux 6.18 kernel package family used by Storage.";
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

    zigPackage = lib.mkOption {
      type = lib.types.package;
      default = if pkgs ? zig_0_16 then pkgs.zig_0_16 else pkgs.zig;
      defaultText = lib.literalExpression ''
        if pkgs ? zig_0_16 then pkgs.zig_0_16 else pkgs.zig
      '';
      description = ''
        Zig package used for development cross-builds. Frozen qualification
        evidence currently requires exactly Zig 0.16.0.
      '';
    };

    enableDocker = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Docker and BuildKit for disposable fixtures.";
    };

    enableAarch64Emulation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable development-only AArch64 emulation. Emulated execution does not
        count as native ARM64 qualification evidence.
      '';
    };

    enableAutomaticNixGc = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Delete unreferenced Nix store paths older than fourteen days each week.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = pkgs.stdenv.hostPlatform.isx86_64;
            message = ''
              storage-devbox.nix describes the x86_64 development VM. Final ARM64
              evidence requires a separate native aarch64 host.
            '';
          }
        ];

        warnings = lib.optional ((cfg.zigPackage.version or "unknown") != "0.16.0") ''
          storageDevbox.zigPackage is version
          ${cfg.zigPackage.version or "unknown"}, not evidence-pinned
          version 0.16.0. It is suitable for ordinary development but not a
          frozen qualification build.
        '';

        boot.kernelPackages = lib.mkDefault cfg.kernelPackages;

        boot.kernelModules = [
          "loop"
        ];

        boot.kernelParams = [
          "systemd.unified_cgroup_hierarchy=1"
          "cgroup_no_v1=all"
          "loop.max_loop=64"
        ];

        boot.kernel.sysctl = {
          "user.max_user_namespaces" = 65536;
          "user.max_mnt_namespaces" = 65536;
          "user.max_pid_namespaces" = 65536;
          "user.max_net_namespaces" = 65536;
          "user.max_uts_namespaces" = 65536;
          "user.max_ipc_namespaces" = 65536;
          "user.max_cgroup_namespaces" = 65536;
          "fs.inotify.max_user_instances" = 8192;
          "fs.inotify.max_user_watches" = 1048576;
        };

        users.users.storage = {
          isNormalUser = true;
          extraGroups = [ "wheel" ] ++ lib.optional cfg.enableDocker "docker";
          initialHashedPassword = toml.password;
          openssh.authorizedKeys.keys = toml."ssh-keys";
          shell = pkgs.zsh;
        };

        programs.zsh.enable = true;

        # Passwordless sudo applies only to the dedicated Storage account.
        security.sudo.extraRules = [
          {
            users = [ "storage" ];

            commands = [
              {
                command = "ALL";
                options = [ "NOPASSWD" ];
              }
            ];
          }
        ];

        services.openssh = {
          enable = true;
          openFirewall = lib.mkDefault true;

          settings = {
            PermitRootLogin = lib.mkDefault "prohibit-password";
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
          };
        };

        services.timesyncd.enable = true;

        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];

          max-jobs = cfg.nixMaxJobs;
          cores = cfg.nixCoresPerJob;
          auto-optimise-store = true;
          trusted-users = [
            "root"
            "@wheel"
          ];
        };

        programs.nix-ld = {
          enable = true;

          libraries = with pkgs; [
            stdenv.cc.cc.lib
            openssl
            zlib
          ];
        };
        
        environment.extraInit = ''
          export PATH="$HOME/.cargo/bin:$PATH"
        '';

        environment.variables = {
          CARGO_BUILD_JOBS = toString cfg.cargoBuildJobs;
          CARGO_INCREMENTAL = "0";
          RUSTUP_TOOLCHAIN = "1.97.1";
          RUST_BACKTRACE = "1";
        };

        environment.systemPackages = with pkgs; [
          # Source and general utilities
          bashInteractive
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          git
          curl
          cacert
          jq
          ripgrep
          file
          which
          tree
          diffutils
          patch

          # Compilation and binary inspection
          gcc
          clang
          lld
          binutils
          pkg-config
          cmake
          gnumake
          perl
          patchelf
          openssl
          zlib
          libseccomp
          pkgsStatic.stdenv.cc

          # Language and repository tooling
          rustup
          python3
          nodejs_22
          cfg.zigPackage
          installPinnedTools

          # Namespace, mount, process, filesystem, and block tools
          util-linux
          iproute2
          procps
          psmisc
          lsof
          strace
          squashfsTools
          e2fsprogs
          xfsprogs
          btrfs-progs
          parted
          gptfdisk
          smartmontools
          nvme-cli
          hdparm
          ethtool

          # Development runtime. Frozen qualification uses a separately reviewed
          # and hashed static runc executable.
          runc
        ];
      }

      (lib.mkIf cfg.enableDocker {
        virtualisation.docker = {
          enable = true;
          daemon.settings.features.buildkit = true;
        };
      })

      (lib.mkIf cfg.enableAarch64Emulation {
        boot.binfmt.emulatedSystems = [
          "aarch64-linux"
        ];
      })

      (lib.mkIf cfg.enableAutomaticNixGc {
        nix.gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 14d";
        };
      })
    ]
  );
}
