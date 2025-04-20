#!/usr/bin/env bash

set -uo pipefail
export LC_ALL=C

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

if [[ -t 1 ]]; then
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  BLUE=$'\033[36m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
else
  GREEN=""
  YELLOW=""
  RED=""
  BLUE=""
  BOLD=""
  RESET=""
fi

section() {
  printf '\n%s%s== %s ==%s\n' "$BOLD" "$BLUE" "$1" "$RESET"
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '%sPASS%s  %-28s %s\n' "$GREEN" "$RESET" "$1" "${2:-}"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '%sWARN%s  %-28s %s\n' "$YELLOW" "$RESET" "$1" "${2:-}"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '%sFAIL%s  %-28s %s\n' "$RED" "$RESET" "$1" "${2:-}"
}

info() {
  printf 'INFO  %-28s %s\n' "$1" "${2:-}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

check_service() {
  local service=$1
  if systemctl is-active --quiet "$service"; then
    pass "$service service" "active"
  else
    fail "$service service" "$(systemctl is-active "$service" 2>/dev/null || true)"
  fi
}

check_socket() {
  local protocol=$1
  local port=$2
  local output

  if [[ "$protocol" == "tcp" ]]; then
    output=$(ss -H -lnt "( sport = :$port )" 2>/dev/null || true)
  else
    output=$(ss -H -lnu "( sport = :$port )" 2>/dev/null || true)
  fi

  if [[ -n "$output" ]]; then
    pass "$protocol/$port listener" "present"
  else
    fail "$protocol/$port listener" "not found"
  fi
}

ping_target() {
  local target=$1
  local output loss rtt

  output=$(ping -n -c 10 -W 2 "$target" 2>&1 || true)
  loss=$(printf '%s\n' "$output" |
    sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' |
    tail -n 1)
  rtt=$(printf '%s\n' "$output" |
    sed -n 's/.*= \([^ ]*\) ms.*/\1/p' |
    tail -n 1)

  if [[ -z "$loss" ]]; then
    fail "internet path $target" "no ping result"
  elif awk "BEGIN { exit !($loss == 0) }"; then
    pass "internet path $target" "loss=${loss}% min/avg/max/mdev=${rtt:-unknown} ms"
  elif awk "BEGIN { exit !($loss < 10) }"; then
    warn "internet path $target" "loss=${loss}% min/avg/max/mdev=${rtt:-unknown} ms"
  else
    fail "internet path $target" "loss=${loss}% min/avg/max/mdev=${rtt:-unknown} ms"
  fi
}

printf '%sDNS benchmark VPS report%s\n' "$BOLD" "$RESET"
printf 'Generated: %s\n' "$(date --iso-8601=seconds)"

section "System"
info "hostname" "$(hostname --fqdn 2>/dev/null || hostname)"
info "virtualization" "$(systemd-detect-virt 2>/dev/null || echo unknown)"
info "kernel" "$(uname -sr)"
info "uptime" "$(awk '
  {
    seconds = int($1)
    days = int(seconds / 86400)
    hours = int((seconds % 86400) / 3600)
    minutes = int((seconds % 3600) / 60)
    printf "%dd %02dh %02dm", days, hours, minutes
  }
' /proc/uptime)"
info "CPU" "$(lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1)"
info "CPU count" "$(nproc)"
info "memory" "$(free -h | awk '/^Mem:/ { print $2 " total, " $3 " used, " $7 " available" }')"
info "root filesystem" "$(df -h / | awk 'NR == 2 { print $2 " total, " $3 " used, " $4 " available" }')"
info "global addresses" "$(ip -brief address show scope global |
  awk '{ printf "%s%s=%s", separator, $1, $3; separator=", " } END { print "" }')"
info "default route" "$(ip route show default | head -n 1)"

failed_units=$(systemctl --failed --no-legend 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
if [[ "$failed_units" == "0" ]]; then
  pass "failed systemd units" "none"
else
  fail "failed systemd units" "$failed_units"
  systemctl --failed --no-pager
fi

section "Services and sockets"
check_service dnsmasq
check_service iperf3
check_service netbird-wt0
check_service sshd
check_socket udp 53
check_socket tcp 53
check_socket tcp 5201
info "UDP/5201 behavior" "iperf3 opens its UDP socket during each client test"

if ip link show wt0 >/dev/null 2>&1; then
  netbird_address=$(ip -brief address show dev wt0 |
    awk '{ print $3 }')
  pass "NetBird interface" "wt0 ${netbird_address:-has no address}"
else
  fail "NetBird interface" "wt0 not found"
fi

section "Local DNS correctness"
udp_answer=$(dig @127.0.0.1 latency.test A +short +norecurse +tries=1 +time=2 |
  tail -n 1)
if [[ "$udp_answer" == "192.0.2.53" ]]; then
  pass "UDP test record" "latency.test -> $udp_answer"
else
  fail "UDP test record" "expected 192.0.2.53, received ${udp_answer:-no answer}"
fi

tcp_answer=$(dig @127.0.0.1 latency.test A +short +tcp +norecurse +tries=1 +time=2 |
  tail -n 1)
if [[ "$tcp_answer" == "192.0.2.53" ]]; then
  pass "TCP test record" "latency.test -> $tcp_answer"
else
  fail "TCP test record" "expected 192.0.2.53, received ${tcp_answer:-no answer}"
fi

recursive_answer=$(dig @127.0.0.1 example.com A +short +recurse +tries=1 +time=2 |
  sed '/^[[:space:]]*$/d' |
  head -n 1)
if [[ -z "$recursive_answer" ]]; then
  pass "public recursion" "disabled"
else
  fail "public recursion" "unexpected external answer: $recursive_answer"
fi

section "Local DNS performance"
temporary_directory=$(mktemp -d /tmp/dns-bench-vps.XXXXXX)
fio_file="/var/tmp/dns-bench-fio.$$"
trap 'rm -rf "$temporary_directory"; rm -f "$fio_file"' EXIT
printf 'latency.test A\n' >"$temporary_directory/queries.txt"

dnsperf_output=$(dnsperf \
  -s 127.0.0.1 \
  -d "$temporary_directory/queries.txt" \
  -l 5 \
  -Q 1000 2>&1)
dnsperf_status=$?
if [[ "$dnsperf_status" == "0" ]]; then
  qps=$(printf '%s\n' "$dnsperf_output" |
    sed -n 's/^[[:space:]]*Queries per second:[[:space:]]*//p' |
    tail -n 1)
  lost=$(printf '%s\n' "$dnsperf_output" |
    sed -n 's/^[[:space:]]*Queries lost:[[:space:]]*//p' |
    tail -n 1)
  pass "dnsperf static record" "qps=${qps:-unknown}, lost=${lost:-unknown}"
else
  fail "dnsperf static record" "dnsperf exited with status $dnsperf_status"
fi

section "Outbound network"
ping_target 1.1.1.1
ping_target 8.8.8.8

external_dns=$(dig @1.1.1.1 example.com A +short +tries=1 +time=2 |
  sed '/^[[:space:]]*$/d' |
  head -n 1)
if [[ -n "$external_dns" ]]; then
  pass "outbound UDP DNS" "1.1.1.1 answered"
else
  warn "outbound UDP DNS" "no answer from 1.1.1.1"
fi

section "VPS resource baselines"
cpu_output=$(sysbench cpu --threads=1 --time=5 run 2>&1)
cpu_status=$?
cpu_events=$(printf '%s\n' "$cpu_output" |
  sed -n 's/^[[:space:]]*events per second:[[:space:]]*//p' |
  tail -n 1)
if [[ "$cpu_status" == "0" ]]; then
  pass "single-thread CPU" "${cpu_events:-unknown} events/s"
else
  warn "single-thread CPU" "sysbench failed"
fi

memory_output=$(sysbench memory --time=5 run 2>&1)
memory_status=$?
memory_rate=$(printf '%s\n' "$memory_output" |
  sed -n 's/.*(\([^()]*\) MiB\/sec).*/\1/p' |
  tail -n 1)
if [[ "$memory_status" == "0" ]]; then
  pass "memory throughput" "${memory_rate:-unknown} MiB/sec"
else
  warn "memory throughput" "sysbench failed"
fi

fio_raw_output="$temporary_directory/fio.raw"
fio_json_output="$temporary_directory/fio.json"
fio_error_output="$temporary_directory/fio.stderr"
if fio \
  --name=dns-bench \
  --filename="$fio_file" \
  --size=128M \
  --rw=randrw \
  --rwmixread=70 \
  --bs=4k \
  --iodepth=16 \
  --direct=1 \
  --runtime=10 \
  --time_based \
  --group_reporting \
  --unlink=1 \
  --output-format=json >"$fio_raw_output" 2>"$fio_error_output"; then
  # Some fio builds print an informational prefix before the JSON document.
  # Keep everything from the opening object onward, then validate it before
  # extracting metrics so a malformed report remains a clean warning.
  sed -n '/^[[:space:]]*{/,$p' "$fio_raw_output" >"$fio_json_output"

  if jq -e '.jobs[0].read.iops != null and .jobs[0].write.iops != null' \
    "$fio_json_output" >/dev/null 2>&1; then
    read_iops=$(jq -r '.jobs[0].read.iops | floor' "$fio_json_output")
    write_iops=$(jq -r '.jobs[0].write.iops | floor' "$fio_json_output")
    pass "random disk I/O" "read=${read_iops} IOPS, write=${write_iops} IOPS"
  else
    fio_detail=$(sed -n '1p' "$fio_error_output")
    if [[ -z "$fio_detail" ]]; then
      fio_detail=$(sed -n '1p' "$fio_raw_output")
    fi
    warn "random disk I/O" "fio returned an invalid report${fio_detail:+: $fio_detail}"
  fi
else
  fio_detail=$(sed -n '1p' "$fio_error_output")
  warn "random disk I/O" \
    "fio failed${fio_detail:+: $fio_detail}"
fi

section "Summary"
printf '%sPassed:%s %d  %sWarnings:%s %d  %sFailed:%s %d\n' \
  "$GREEN" "$RESET" "$PASS_COUNT" \
  "$YELLOW" "$RESET" "$WARN_COUNT" \
  "$RED" "$RESET" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
