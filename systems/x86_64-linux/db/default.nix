{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  inputs,

  # Additional metadata is provided by Snowfall Lib.
  system, # The system architecture for this host (eg. `x86_64-linux`).
  target, # The Snowfall Lib target for this system (eg. `x86_64-iso`).
  format, # A normalized name for the system target (eg. `iso`).
  virtual, # A boolean to determine whether this system is a virtual target using nixos-generators.
  systems, # An attribute map of your defined hosts.

  # All other arguments come from the system system.
  config,
  ...
}:
let
  toml = lib.importTOML ../../../secrets/crypt.toml;
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  common.enable = true;

  networking = {
    useDHCP = false;
    defaultGateway = {
      address = toml.${config.networking.hostName}.gateway;
      interface = "ens3";
    };
    nameservers = [
      "46.38.225.230"
      "46.38.252.230"
    ];
    interfaces = {
      ens3 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = toml.${config.networking.hostName}.address;
            prefixLength = 22;
          }
        ];
      };
      ens4.ipv4.addresses = [
        {
          address = "10.10.0.1";
          prefixLength = 24;
        }
      ];
    };
  };

  # Configure sops-nix
  sops = {
    defaultSopsFile = ./files/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.pgadmin_password = {
      owner = "pgadmin";
      mode = "0400";
    };
    secrets.dbadmin_password = {
      owner = "postgres";
      mode = "0400";
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      5050
    ];
    interfaces."ens4".allowedTCPPorts = [ 5432 ];
  };

  services.qemuGuest.enable = true;

  deploy = {
    address = toml.${config.networking.hostName}.address;
    remoteBuild = true;
    user = "nixos";
  };

  systemd.services.init-dbadmin = {
    description = "Create dbadmin superuser role";
    wantedBy = [ "multi-user.target" ];
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };

    script = ''
      set -euo pipefail

      PW="$(cat ${config.sops.secrets.dbadmin_password.path})"

      ${config.services.postgresql.package}/bin/psql \
        -v ON_ERROR_STOP=1 \
        -v pw="$PW" \
        <<'EOF'
      SELECT format(
        'CREATE ROLE dbadmin WITH LOGIN PASSWORD %L SUPERUSER',
        :'pw'
      )
      WHERE NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'dbadmin'
      );
      \gexec
      EOF
    '';
  };

  services = {
    postgresql = {
      enable = true;
      package = pkgs.postgresql_18;
      authentication = lib.mkForce ''
        # local connections via unix socket
        local all all peer
        host all all 127.0.0.1/32 md5
        host all all 10.10.0.0/16 md5
      '';
      settings = {
        listen_addresses = lib.mkForce "10.10.0.1";
        shared_buffers = "2GB";
        effective_cache_size = "5GB";
        work_mem = "32MB";
        maintenance_work_mem = "512MB";
        max_connections = "100";
        wal_buffers = "16MB";
        checkpoint_completion_target = "0.9";
        random_page_cost = "1.1";
        effective_io_concurrency = "200";
      };
    };
    pgadmin = {
      enable = true;
      port = 5050;
      initialEmail = toml.db.pgadmin_email;
      initialPasswordFile = config.sops.secrets.pgadmin_password.path;
      settings = {
        DEFAULT_SERVER = "0.0.0.0";
      };
    };
  };

  services.watcher = {
    enable = true;
    interval = "30s";

    settings.metrics.enable = true;

    services.postgresql = {
      onFailed = true;
      onInactive = false; # Don't restart if intentionally stopped

      healthCheck = {
        enable = true;
        type = "exec";
        target = "${config.services.postgresql.package}/bin/pg_isready -h 10.10.0.1";
        timeout = "5s";
        failuresBeforeRestart = 3; # Conservative - wait for 3 failures
      };

      # Be conservative with database restarts
      rateLimiting = {
        maxRestarts = 3;
        windowMinutes = 30;
      };
    };
  };
}
