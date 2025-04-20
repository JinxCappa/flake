{
  config,
  lib,
  pkgs,
  ...
}:
let
  toml = lib.importTOML ../../../secrets/crypt.toml;

  vpsCheck = pkgs.writeShellApplication {
    name = "dns-bench-vps";
    runtimeInputs = with pkgs; [
      coreutils
      dnsperf
      dnsutils
      fio
      gawk
      gnugrep
      gnused
      hostname
      iproute2
      iputils
      jq
      procps
      sysbench
      systemd
      util-linux
    ];
    text = builtins.readFile ./scripts/vps-check.sh;
  };

in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  common.enable = true;

  sops = {
    defaultSopsFile = ./files/secrets.yaml;
    secrets."netbird-setup-key" = { };
  };

  networking = {
    hostName = "dns-bench";

    # common.enable leaves the firewall off. This public trial host overrides
    # that default and exposes only SSH plus the iperf3 test endpoint.
    firewall = {
      enable = lib.mkForce true;
      allowedTCPPorts = [
        22
        53
      ];
      allowedUDPPorts = [
        53
        5201
      ];
    };
  };

  services.dnsmasq = {
    enable = true;

    # Keep the host's own resolver supplied by DHCP. This dnsmasq instance is
    # an isolated latency target, not the VPS's recursive resolver.
    resolveLocalQueries = false;
    settings = {
      bind-interfaces = true;
      listen-address = [
        "0.0.0.0"
        "::"
      ];

      # Do not offer public recursion. Only the static .test answer below is
      # useful, which avoids creating an open DNS resolver.
      no-hosts = true;
      no-resolv = true;
      local = "/test/";
      address = "/latency.test/192.0.2.53";
    };
  };

  services.netbird.clients.wt0 = {
    interface = "wt0";
    port = 51820;
    hardened = true;
    managementUrl = toml.netbird.management_url;

    login = {
      enable = true;
      setupKeyFile = config.sops.secrets."netbird-setup-key".path;
    };
  };

  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    # DNS query latency, protocol inspection, and load testing.
    dnsutils
    dnsperf
    doggo
    ldns

    # Round-trip time, path, jitter, packet loss, and throughput.
    fping
    gping
    iperf3
    iputils
    mtr
    traceroute

    # Connection and packet-level diagnostics.
    curl
    ethtool
    iproute2
    nmap
    socat
    tcpdump
    whois

    # Check whether a cheap VPS is CPU- or disk-constrained.
    fio
    sysbench

    vpsCheck
  ];
}
