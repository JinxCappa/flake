#! /usr/bin/env bash
set -eou pipefail

scriptPath="$(dirname $(realpath $0))"
package=$( echo "$scriptPath" | tr '/' '\n' | tail -n 1)

if [ "$scriptPath" != "$PWD" ]; then
  cd "$scriptPath"
fi

nix build --no-link --print-out-paths -L --fallback . | xargs -I {} attic push "ci:$ATTIC_CACHE" {};