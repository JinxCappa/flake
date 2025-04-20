{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.bootstrapConsole;
  instructionCommands = lib.concatMapStringsSep "\n" (
    instruction: "echo ${lib.escapeShellArg instruction}"
  ) cfg.instructions;
in
{
  options.bootstrapConsole = {
    enable = lib.mkEnableOption "pre-login bootstrap network information";

    title = lib.mkOption {
      type = lib.types.str;
      default = "Bootstrap network:";
      description = "Heading displayed above the network interfaces.";
    };

    waitSeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 15;
      description = "Maximum number of seconds to wait for a global IPv4 address.";
    };

    instructions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Login instructions displayed below the network interfaces.";
    };
  };

  config = lib.mkIf cfg.enable {
    # NixOS agetty reads /run/issue.d before displaying every local login
    # prompt. Generate the file before getty-pre.target so the first prompt is
    # useful even when the machine's DHCP address and MAC are not yet known.
    systemd.services.bootstrap-console-network-info = {
      description = "Show bootstrap network information on local consoles";
      wantedBy = [ "getty.target" ];
      before = [ "getty-pre.target" ];
      wants = [
        "getty-pre.target"
        "network.target"
      ];
      after = [ "network.target" ];

      serviceConfig.Type = "oneshot";

      script = ''
        elapsed=0
        while [ "$elapsed" -lt ${toString cfg.waitSeconds} ]; do
          addresses="$(${pkgs.iproute2}/bin/ip -o -4 address show scope global)"
          if [ -n "$addresses" ]; then
            break
          fi
          ${pkgs.coreutils}/bin/sleep 1
          elapsed=$((elapsed + 1))
        done

        ${pkgs.coreutils}/bin/mkdir -p /run/issue.d
        {
          echo
          echo ${lib.escapeShellArg cfg.title}

          for iface_path in /sys/class/net/*; do
            interface="$(${pkgs.coreutils}/bin/basename "$iface_path")"
            if [ "$interface" = "lo" ]; then
              continue
            fi

            mac="$(${pkgs.coreutils}/bin/cat "$iface_path/address")"
            ipv4="$(${pkgs.iproute2}/bin/ip -o -4 address show dev "$interface" scope global | ${pkgs.gawk}/bin/awk '{ printf "%s%s", separator, $4; separator = ", " }')"
            ipv6="$(${pkgs.iproute2}/bin/ip -o -6 address show dev "$interface" scope global | ${pkgs.gawk}/bin/awk '{ printf "%s%s", separator, $4; separator = ", " }')"

            if [ -z "$ipv4" ]; then
              ipv4="not acquired"
            fi
            if [ -z "$ipv6" ]; then
              ipv6="not acquired"
            fi

            printf '  %s\n    IPv4: %s\n    IPv6: %s\n    MAC:  %s\n' \
              "$interface" "$ipv4" "$ipv6" "$mac"
          done

          echo
          ${instructionCommands}
        } > /run/issue.d/50-bootstrap-network.issue
      '';
    };
  };
}
