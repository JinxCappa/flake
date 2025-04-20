#!/usr/bin/env bash
set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOML="$FLAKE_DIR/secrets/crypt.toml"
BASE_SYSTEM="base"
BASE_HW_CONFIG="./systems/x86_64-linux/$BASE_SYSTEM/hardware-configuration.nix"

# Read a value from crypt.toml
toml_get() {
  local section="$1" key="$2"
  sed -n "/^\[$section\]/,/^\[/p" "$TOML" | grep "^$key " | head -1 | sed 's/.*= *"\(.*\)"/\1/'
}

# Get deploy user from default.nix
get_user() {
  grep -oE 'user = "[^"]+"' "$FLAKE_DIR/systems/x86_64-linux/$1/default.nix" 2>/dev/null \
    | head -1 | sed 's/user = "\(.*\)"/\1/'
}

has_extra_files() { [[ -d "$FLAKE_DIR/systems/x86_64-linux/$1/extra-files" ]]; }
has_luks() { grep -q 'type = "luks"' "$FLAKE_DIR/systems/x86_64-linux/$1/disko.nix" 2>/dev/null; }

sync_sops_host_entry() {
  local system="$1" age_key="$2"
  local sops_config="$FLAKE_DIR/.sops.yaml"
  local tmp1 tmp2

  tmp1="$(mktemp)"
  tmp2="$(mktemp)"

  awk -v system="$system" -v age_key="$age_key" '
    BEGIN {
      anchor = "  - &" system " " age_key
      found = 0
    }
    $0 ~ ("^[[:space:]]*-[[:space:]]*&" system "[[:space:]]+age") {
      print anchor
      found = 1
      next
    }
    /^creation_rules:$/ && !found {
      print anchor
      found = 1
    }
    { print }
  ' "$sops_config" > "$tmp1"

  awk -v system="$system" '
    BEGIN {
      found = 0
      skipping = 0
      rule1 = "  - path_regex: " system "/files/.*"
      rule2 = "    key_groups:"
      rule3 = "      - age:"
      rule4 = "          - *jinx"
      rule5 = "          - *" system
    }
    skipping {
      if ($0 ~ /^  - path_regex:/) {
        skipping = 0
      } else {
        next
      }
    }
    $0 ~ ("^  - path_regex: " system "/files/\\.\\*$") {
      print rule1
      print rule2
      print rule3
      print rule4
      print rule5
      found = 1
      skipping = 1
      next
    }
    !found && $0 ~ /^  - path_regex: \.\*\/files\/crypt\/\.\*$/ {
      print rule1
      print rule2
      print rule3
      print rule4
      print rule5
      found = 1
    }
    { print }
    END {
      if (!found) {
        print rule1
        print rule2
        print rule3
        print rule4
        print rule5
      }
    }
  ' "$tmp1" > "$tmp2"

  mv "$tmp2" "$sops_config"
  rm -f "$tmp1"
}

update_sops_files() {
  local system_dir="$1"
  local found=0

  while IFS= read -r file; do
    found=1
    echo "Updating sops keys for ${file#$FLAKE_DIR/}"
    sops updatekeys -y "$file"
  done < <(rg -l '^sops:' "$system_dir")

  if [[ $found -eq 0 ]]; then
    echo "No sops-managed files found under ${system_dir#$FLAKE_DIR/}"
  fi
}

# Discover systems
systems=()
for dir in "$FLAKE_DIR"/systems/x86_64-linux/*/; do
  name="$(basename "$dir")"
  [[ "$name" == "archive" || "$name" == "$BASE_SYSTEM" ]] && continue
  [[ -f "$dir/default.nix" ]] && systems+=("$name")
done

if [[ ${#systems[@]} -eq 0 ]]; then
  echo "No systems found"
  exit 1
fi

echo "=== nixos-anywhere installer ==="
echo
echo "Available systems:"
for i in "${!systems[@]}"; do
  name="${systems[$i]}"
  flags=()
  has_luks "$name" && flags+=("luks")
  has_extra_files "$name" && flags+=("extra-files")
  mode="${flags[*]:-standard}"
  echo "  $((i + 1))) $name [$mode]"
done

read -rp "Select system [1-${#systems[@]}]: " system_idx
system="${systems[$((system_idx - 1))]}"
arch="x86_64-linux"

# Get address
address="$(toml_get "$system" "address")"
if [[ -z "$address" ]]; then
  read -rp "No address found for '$system'. Enter IP: " address
fi

# Get user
default_user="$(get_user "$system")"
default_user="${default_user:-nixos}"

read -rp "Connect as root? [y/N]: " use_root
if [[ "$use_root" =~ ^[yY]$ ]]; then
  user="root"
else
  user="$default_user"
fi

# Build bootstrap install command using the base system.
cmd=(nixos-anywhere)

cmd+=(
  --flake ".#$BASE_SYSTEM"
  --generate-hardware-config nixos-generate-config "$BASE_HW_CONFIG"
)

cmd+=(--build-on remote "$user@$address")

echo
echo "Will run:"
echo "  ${cmd[*]}"
echo
read -rp "Proceed? [y/N]: " confirm
[[ "$confirm" =~ ^[yY]$ ]] || exit 0

cd "$FLAKE_DIR"
"${cmd[@]}"

# Wait for server to come back up
echo
echo "=== Waiting for $system to come back online ==="
until ping -c1 -W2 "$address" &>/dev/null; do
  sleep 2
done
echo "Host is responding to ping"

# Remove old host keys and accept new ones
echo "=== Updating SSH known_hosts ==="
ssh-keygen -R "$address" 2>/dev/null || true

retries=0
until ssh-keyscan -H "$address" >> ~/.ssh/known_hosts 2>/dev/null; do
  retries=$((retries + 1))
  if [[ $retries -ge 30 ]]; then
    echo "Failed to scan SSH keys after 30 attempts"
    exit 1
  fi
  echo "SSH not ready yet, retrying ($retries/30)..."
  sleep 5
done
echo "Updated known_hosts for $address"

echo
echo "=== Fetching host age key ==="
host_age_key="$(ssh-keyscan "$address" 2>/dev/null | ssh-to-age | tail -n1)"
if [[ -z "$host_age_key" ]]; then
  echo "Failed to derive age key from $address"
  exit 1
fi
echo "Resolved $system age key: $host_age_key"

echo
echo "=== Updating .sops.yaml ==="
sync_sops_host_entry "$system" "$host_age_key"

echo
echo "=== Re-encrypting $system secrets ==="
update_sops_files "$FLAKE_DIR/systems/$arch/$system"

# Deploy to set up home-manager
echo
echo "=== Running deploy for $system ==="
deploy -s ".#$system"
