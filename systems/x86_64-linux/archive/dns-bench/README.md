# DNS provider trial host

This NixOS target is a disposable x86_64 VPS for comparing cloud-provider
network quality before committing to a longer contract. It runs a persistent
`iperf3` endpoint and a non-recursive `dnsmasq` test server, and includes DNS,
route, packet, throughput, CPU, and disk diagnostic tools.

## Install

Boot the provider's rescue image and identify the system disk:

```console
lsblk -dpno NAME,SIZE,MODEL
```

`disko.nix` defaults to `/dev/vda`. Change that path before proceeding if the
rescue image reports `/dev/sda`, an NVMe device, or a stable `/dev/disk/by-id`
path. The installation erases the selected disk.

Install with `nixos-anywhere`, substituting the rescue image's SSH user and
public address:

```console
nix run github:nix-community/nixos-anywhere -- \
  --flake .#dns-bench <installer-user>@<vps-ip>
```

The installed system uses the repository's `nixos` SSH keys:

```console
ssh nixos@<vps-ip>
dns-bench-vps
```

`dns-bench-vps` produces a color-coded local report covering system health,
service and socket state, DNS correctness and recursion safety, local DNS
throughput, outbound connectivity, CPU, memory, and temporary random disk I/O.
It exits unsuccessfully when any required check fails, making it suitable for
capturing in provisioning or trial-host logs.

The host joins the self-hosted NetBird network as `dns-bench` using the
SOPS-encrypted `netbird-setup-key`. The report verifies the `netbird-wt0`
service and `wt0` interface. Run the client report against both the public and
NetBird addresses to compare the underlay with the production overlay path.

## Compare providers from your computer

Run the same tests at several times of day and save the raw results. Focus on
median and tail latency, jitter, packet loss, and route stability rather than
only the lowest single ping.

```console
ping -c 100 <vps-ip>
mtr --report-wide --report-cycles 100 <vps-ip>

# Upload, download, and UDP jitter/loss
iperf3 -c <vps-ip> -t 30 -P 4
iperf3 -c <vps-ip> -R -t 30 -P 4
iperf3 -c <vps-ip> -u -b 20M -t 30
```

Measure both UDP and TCP query latency against the built-in static record:

```console
dig @<vps-ip> latency.test A +norecurse +tries=1 +time=2 +stats
dig @<vps-ip> latency.test A +tcp +norecurse +tries=1 +time=2 +stats
```

Both commands should return `192.0.2.53`, an address reserved for
documentation. `dnsmasq` has no upstream resolvers configured, so this host
cannot be used for public recursive DNS.

On the VPS, `dnsperf` can load-test the eventual resolver, while `tcpdump`,
`mtr`, `fping`, `doggo`, `drill`, `nmap`, and `socat` help diagnose anomalies.
`fio` and `sysbench` provide a quick check for noisy-neighbor CPU or disk
contention.

The firewall exposes SSH, DNS on TCP/UDP port 53, and the unauthenticated
`iperf3` service on TCP/UDP port 5201. That is convenient for short trials.
For a long-lived deployment, restrict ports 53 and 5201 to the computer's
public source address or disable the test services.

## Automated client report

Copy [`scripts/dns-bench-client`](scripts/dns-bench-client) to each client
location, make it executable, and supply the VPS address:

```console
chmod +x dns-bench-client
./dns-bench-client <vps-ip>
```

When Nix is installed, the client script automatically re-executes itself in
an ephemeral `nix shell` containing `dig`, `iperf3`, `jq`, `mtr`, and its
required shell utilities. Nothing needs to be installed or activated manually;
the first run may download the packages. Without Nix, those commands must
already be installed. The `mtr` route test may still require elevated
raw-socket permission on some operating systems. When necessary, the script
uses `sudo` for that test alone and may request the client's password.

The report covers DNS correctness, recursion safety, UDP/TCP DNS latency
percentiles, ICMP latency and loss, the route when `mtr` is available,
bidirectional TCP throughput, and UDP jitter and loss.

Test duration and load can be adjusted without editing the script:

```console
DNS_SAMPLES=100 \
PING_COUNT=100 \
IPERF_SECONDS=30 \
IPERF_PARALLEL=4 \
IPERF_UDP_RATE=50M \
  ./dns-bench-client <vps-ip>
```
