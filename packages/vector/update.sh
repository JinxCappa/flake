#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl gnused jq nix-prefetch
set -eou pipefail

ROOT="$(dirname "$(readlink -f "$0")")"

CURRENT_VERSION=$(nix flake show --json --all-systems $ROOT 2>/dev/null | jq -r '.packages."x86_64-linux".default.name' | cut -d '-' -f 2)
LATEST_VERSION=$(curl --fail --silent https://api.github.com/repos/vectordotdev/vector/releases/latest | jq --raw-output .tag_name | sed 's/v//')

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "vector already at latest version $CURRENT_VERSION, exiting"
    exit 0
else
    sed -i "s/version = \".*\"/version = \"${LATEST_VERSION}\"/" "$ROOT/default.nix"
fi

function updateHashes() {
    echo "Updating flake dependencies..."
    nix flake update $ROOT &>/dev/null
    echo "Updating source hash..."
    URL="https://github.com/vectordotdev/vector/archive/refs/tags/v${LATEST_VERSION}.tar.gz"
    HASH=$(nix hash convert --hash-algo sha256 "$(nix-prefetch-url --type sha256 --unpack $URL 2>/dev/null)")
    sed -i "s,hash = \"sha256.*\",hash = \"${HASH}\"," "$ROOT/default.nix"

    echo "Updating cargo hash..."
    nix build "$ROOT" > $ROOT/vector-build.log 2>&1 || true
    cargoHash=$(grep "got:" $ROOT/vector-build.log | tr -d '[:space:]' | cut -d':' -f2)
    sed -i "s,cargoHash = \"sha256.*\",cargoHash = \"${cargoHash}\"," "$ROOT/default.nix"
    rm $ROOT/vector-build.log

    echo "cleaning up store..."
    nix-collect-garbage -d &>/dev/null

    echo "Updated vector to version $LATEST_VERSION"
}

updateHashes