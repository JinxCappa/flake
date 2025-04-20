{
  description = "Jinx Flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Custom packages and modules
    jinx-pkgs.url = "github:jinxcappa/nix-pkgs";
    jinx-modules = {
      url = "github:JinxCappa/nix-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Darwin
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS tools
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:numtide/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };

    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Homebrew for Darwin
    brew-src = {
      url = "github:Homebrew/brew";
      flake = false;
    };

    nix-homebrew = {
      url = "github:JinxCappa/nix-homebrew";
      inputs.brew-src.follows = "brew-src";
    };

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    supabase-homebrew-tap = {
      url = "github:supabase/homebrew-tap";
      flake = false;
    };

    # Hardware support
    orangepi6plus = {
      url = "github:JinxCappa/nixos-orangepi6plus";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Armbian's CIX P1 UEFI/ACPI kernel config and patch assets.
    armbian-build = {
      url = "github:armbian/build/4451999a153c8cf48ae5ff35541b1d994d5903c2";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      rawFlakeOutputs = inputs.jinx-modules.lib.mkFlake {
        inherit inputs;
        src = ./.;
        overlays = inputs.jinx-pkgs.lib.overlays.cached ++ [
          inputs.orangepi6plus.overlays.default
        ];

        customLib = inputs.jinx-modules.lib;

        commonNixosModules = with inputs; [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          (vscode-server + "/modules/vscode-server")
          sops-nix.nixosModules.sops
          jinx-modules.nixosModules.default
          ./modules/nixos/common
        ];

        commonDarwinModules = with inputs; [
          home-manager.darwinModules.home-manager
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              user = "jinx";
              taps = {
                "homebrew/homebrew-core" = inputs.homebrew-core;
                "homebrew/homebrew-cask" = inputs.homebrew-cask;
                "supabase/homebrew-tap" = inputs.supabase-homebrew-tap;
              };
              mutableTaps = true;
            };
          }
        ];

        commonHomeModules = with inputs; [
          sops-nix.homeManagerModules.sops
          ({ lib, pkgs, ... }: {
            sops = lib.optionalAttrs (pkgs ? sops-install-secrets) {
              package = lib.mkDefault pkgs.sops-install-secrets;
            };
          })
        ];
      };

      # nixpkgs unstable no longer supports x86_64-darwin. Keep the old
      # configuration files in the repository, but do not expose/evaluate them.
      flakeOutputs = rawFlakeOutputs // {
        darwinConfigurations = nixpkgs.lib.filterAttrs (
          name: _: rawFlakeOutputs._internal.discoveredSystems.${name}.arch != "x86_64-darwin"
        ) rawFlakeOutputs.darwinConfigurations;
        homeConfigurations = nixpkgs.lib.filterAttrs (
          name: _: rawFlakeOutputs._internal.discoveredHomes.${name}.arch != "x86_64-darwin"
        ) rawFlakeOutputs.homeConfigurations;
      };

      deploy = inputs.jinx-modules.lib.mkDeploy {
        inherit self;
        inherit (inputs) deploy-rs nixpkgs;
      };

      installerPackages =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          netboot = self.nixosConfigurations.installer-netboot.config.system.build;
        in
        {
          installer-iso = self.nixosConfigurations.installer-iso.config.system.build.isoImage;
          installer-netboot = pkgs.linkFarm "nixos-anywhere-installer-netboot" [
            {
              name = "bzImage";
              path = "${netboot.kernel}/bzImage";
            }
            {
              name = "initrd";
              path = netboot.netbootRamdisk;
            }
            {
              name = "netboot.ipxe";
              path = netboot.netbootIpxeScript;
            }
            {
              name = "netboot.tar.xz";
              path = netboot.image;
            }
          ];
        };

      installerPackagesBySystem = {
        x86_64-linux = installerPackages;
        aarch64-darwin = installerPackages;
      };

      sbcImagePackages = {
        orange-pi-6-plus-bootstrap-image =
          self.nixosConfigurations.orange-pi-6-plus.config.system.build.sdImage;
        rock-5a-bootstrap-image = self.nixosConfigurations.rock-5a.config.system.build.sdImage;
        rockpi-4b-bootstrap-image = self.nixosConfigurations.rockpi-4b.config.system.build.sdImage;
      };

      # Expose the Linux derivations from common developer and builder systems.
      # Nix will use a configured aarch64-linux remote builder when necessary.
      sbcImagePackagesBySystem = {
        aarch64-linux = sbcImagePackages;
        aarch64-darwin = sbcImagePackages;
        x86_64-linux = sbcImagePackages;
      };

      # Helper to create fetch-host-key app for a given system
      mkFetchHostKeyApp =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          toml = fromTOML (builtins.readFile ./secrets/crypt.toml);
          hostAddresses = builtins.concatStringsSep "\n" (
            builtins.filter (x: x != "") (
              map (
                name:
                let
                  val = toml.${name};
                in
                if builtins.isAttrs val && builtins.hasAttr "address" val then "${name}=${val.address}" else ""
              ) (builtins.attrNames toml)
            )
          );
        in
        {
          type = "app";
          program = toString (
            pkgs.writeShellScript "fetch-host-key" ''
              set -e
              HOST="''${1:-}"

              # Host lookup table (generated at build time)
              HOSTS="${hostAddresses}"

              if [ -z "$HOST" ]; then
                echo "Usage: nix run .#fetch-host-key <hostname>"
                echo ""
                echo "Available hosts:"
                echo "$HOSTS" | cut -d= -f1 | sort
                exit 1
              fi

              # Look up address
              ADDR=$(echo "$HOSTS" | grep "^$HOST=" | cut -d= -f2)
              if [ -z "$ADDR" ]; then
                echo "Host '$HOST' not found in secrets/crypt.toml"
                echo ""
                echo "Available hosts:"
                echo "$HOSTS" | cut -d= -f1 | sort
                exit 1
              fi

              echo "Fetching age public key from $HOST ($ADDR)..."
              ssh -o StrictHostKeyChecking=accept-new nixos@"$ADDR" \
                "sudo ${pkgs.age}/bin/age-keygen -y /root/.config/sops/age/keys.txt"
            ''
          );
        };

      # Helper to create check-reboot app for a given system
      mkCheckRebootApp =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          toml = fromTOML (builtins.readFile ./secrets/crypt.toml);
          hostAddresses = builtins.concatStringsSep "\n" (
            builtins.filter (x: x != "") (
              map (
                name:
                let
                  val = toml.${name};
                in
                if builtins.isAttrs val && builtins.hasAttr "address" val then "${name}=${val.address}" else ""
              ) (builtins.attrNames toml)
            )
          );
        in
        {
          type = "app";
          program = toString (
            pkgs.writeShellScript "check-reboot" ''
              set -e

              HOSTS="${hostAddresses}"
              DO_REBOOT=false
              HOST=""

              # Parse arguments
              while [ $# -gt 0 ]; do
                case "$1" in
                  --reboot) DO_REBOOT=true ;;
                  *) HOST="$1" ;;
                esac
                shift
              done

              check_host() {
                local name="$1"
                local addr="$2"

                result=$(ssh -n -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new nixos@"$addr" '
                  booted=$(readlink /run/booted-system)
                  current=$(readlink /run/current-system)
                  running_kernel=$(uname -r)
                  # Get new kernel version from modules directory
                  new_kernel=$(ls /run/current-system/kernel-modules/lib/modules/ 2>/dev/null | head -1)
                  [ -z "$new_kernel" ] && new_kernel="unknown"

                  if [ "$booted" != "$current" ]; then
                    echo "REBOOT_NEEDED:$running_kernel -> $new_kernel"
                  else
                    echo "OK:$running_kernel"
                  fi
                ' 2>/dev/null) || result="UNREACHABLE:"

                local status=$(echo "$result" | cut -d: -f1)
                local info=$(echo "$result" | cut -d: -f2)

                if [ "$status" = "REBOOT_NEEDED" ]; then
                  printf "%-15s %-20s %s\n" "$name" "$addr" "REBOOT NEEDED ($info)"
                  echo "$name=$addr" >> /tmp/reboot_needed_$$
                else
                  printf "%-15s %-20s %s\n" "$name" "$addr" "$status ($info)"
                fi
              }

              reboot_host() {
                local name="$1"
                local addr="$2"
                echo "Rebooting $name ($addr)..."
                ssh -n -o ConnectTimeout=5 nixos@"$addr" 'sudo reboot' 2>/dev/null || true
              }

              rm -f /tmp/reboot_needed_$$

              printf "%-15s %-20s %s\n" "HOST" "ADDRESS" "STATUS"
              printf "%-15s %-20s %s\n" "----" "-------" "------"

              if [ -n "$HOST" ]; then
                # Check single host
                ADDR=$(echo "$HOSTS" | grep "^$HOST=" | cut -d= -f2)
                if [ -z "$ADDR" ]; then
                  echo "Host '$HOST' not found"
                  exit 1
                fi
                check_host "$HOST" "$ADDR"
              else
                # Check all hosts (use here-string to avoid subshell)
                while IFS='=' read -r name addr; do
                  check_host "$name" "$addr"
                done <<< "$HOSTS"
              fi

              # Reboot hosts if requested
              if [ "$DO_REBOOT" = true ] && [ -f /tmp/reboot_needed_$$ ]; then
                echo ""
                echo "Rebooting hosts that need it..."
                while IFS='=' read -r name addr; do
                  reboot_host "$name" "$addr"
                done < /tmp/reboot_needed_$$
                rm -f /tmp/reboot_needed_$$
              fi
            ''
          );
        };

    in
    flakeOutputs
    // {
      inherit deploy;

      # Installer and SBC images.
      #   nix build .#installer-iso           -> bootable ISO (result/iso/*.iso)
      #   nix build .#installer-netboot       -> PXE kernel + initrd + ipxe script
      #   nix build .#orange-pi-6-plus-bootstrap-image -> reusable Orange Pi 6 Plus image
      #   nix build .#rock-5a-bootstrap-image -> reusable Rock 5A image
      #   nix build .#rockpi-4b-bootstrap-image -> reusable Rock Pi 4B+ eMMC image
      packages =
        let
          packagesWithInstallers = nixpkgs.lib.recursiveUpdate (flakeOutputs.packages or { }
          ) installerPackagesBySystem;
        in
        nixpkgs.lib.recursiveUpdate packagesWithInstallers sbcImagePackagesBySystem;

      # Fetch age public key from a deployed host
      apps.x86_64-linux.fetch-host-key = mkFetchHostKeyApp "x86_64-linux";
      apps.aarch64-linux.fetch-host-key = mkFetchHostKeyApp "aarch64-linux";

      # Check if hosts need a reboot after deployment
      apps.x86_64-linux.check-reboot = mkCheckRebootApp "x86_64-linux";
      apps.aarch64-linux.check-reboot = mkCheckRebootApp "aarch64-linux";
      apps.aarch64-darwin.check-reboot = mkCheckRebootApp "aarch64-darwin";

      # Only generate deploy checks for Linux systems
      checks = builtins.mapAttrs (system: deploy-lib: deploy-lib.deployChecks self.deploy) (
        nixpkgs.lib.filterAttrs (system: _: nixpkgs.lib.hasSuffix "-linux" system) inputs.deploy-rs.lib
      );
    };
}
