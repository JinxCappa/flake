#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl gnused jq nix-prefetch
set -eou pipefail

ROOT="$(dirname "$(readlink -f "$0")")"

CURRENT_VERSION=$(cat $ROOT/default.nix | grep "rev =" | tr -d '[:space:]' | cut -d '"' -f 2)
LATEST_VERSION=$(curl --fail --silent https://api.github.com/repos/ohmyzsh/ohmyzsh/commits | jq --raw-output '.[0].sha')

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "oh-my-zsh already at latest version $CURRENT_VERSION, exiting"
    exit 0
else
    sed -i "s/rev = \".*\"/rev = \"${LATEST_VERSION}\"/" "$ROOT/default.nix"
    LATEST_DATE=$(curl --fail --silent https://api.github.com/repos/ohmyzsh/ohmyzsh/commits | jq --raw-output '.[0].commit.committer.date' | cut -d'T' -f1)
    sed -i "s/version = \".*\"/version = \"${LATEST_DATE}\"/" "$ROOT/default.nix"
fi

function updateHashes() {
    echo "Updating flake dependencies..."
    nix flake update $ROOT &>/dev/null
    echo "Updating source hash..."
    URL="https://github.com/ohmyzsh/ohmyzsh/archive/refs/heads/master.tar.gz"
    HASH=$(nix hash convert --hash-algo sha256 "$(nix-prefetch-url --type sha256 --unpack $URL 2>/dev/null)")
    sed -i "s,sha256 = \"sha256.*\",sha256 = \"${HASH}\"," "$ROOT/default.nix"

    echo "cleaning up store..."
    nix-collect-garbage -d &>/dev/null

    echo echo "Updated vector to version $LATEST_VERSION"
}

updateHashes
