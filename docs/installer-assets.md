# Installer assets

The **Installer assets** GitHub Actions workflow builds both bootstrap
environments on native x86_64 Linux runners. Run it from the Actions page and
download only the ISO or netboot bundle you need from the completed workflow.

## NixOS variant

The `nixos-installer-iso` artifact contains:

- `nixos-anywhere-installer.iso`

The separate `nixos-installer-netboot` artifact contains:

- `bzImage`
- `initrd`
- `netboot.ipxe`
- `netboot.tar.xz`

Both variants display every non-loopback interface's IPv4, IPv6, and MAC
address before the local login prompt. The directly accessible account is
`nixos`: use `nixos` / `nixos` locally, or connect with an authorized key:

```console
ssh nixos@<displayed-ipv4-address>
nix run github:numtide/nixos-anywhere -- \
  --flake .#<host> nixos@<displayed-ipv4-address>
```

The `nixos` account has passwordless sudo. SSH password authentication is
disabled. During installation, nixos-anywhere uses sudo to perform its internal
privilege escalation.

The workflow builds `.#installer-iso` and `.#installer-netboot`, pushes their
closures to Cellar when its repository secrets are available, and then
collects the files into the artifact.

## Alpine variant

The `alpine-installer-iso` artifact contains the customized Alpine bootstrap
ISO and its checksum files.

The separate `alpine-installer-netboot` artifact contains:

- `boot.ipxe`
- `vmlinuz-lts`
- `initramfs-lts`
- `modloop-lts`
- `bootstrap.apkovl.tar.gz`
- `SHA256SUMS`

Serve the `ipxe/` directory over HTTP and chain `boot.ipxe`, or flash the ISO
to removable media.

The Alpine console displays the same per-interface IPv4, IPv6, MAC, and login
instructions as the NixOS installer assets before the local login prompt.
Alpine also includes Bash and the other nixos-anywhere target utilities, and
uses the `nixos` account with passwordless sudo. Its local password is `nixos`
and SSH remains key-only.

Alpine disables IPv4 link-local fallback and waits indefinitely for a
non-`169.254/16` DHCPv4 lease before showing the login prompt. This prevents an
unreachable APIPA address from looking like a usable installer endpoint.

Both Alpine boot paths pass `kexec_load_disabled=0`. Alpine's LTS kernel
disables the kexec syscall by default, while nixos-anywhere requires it to hand
off from Alpine to its NixOS installer environment.

All four artifacts are retained for 14 days. Pull requests build the assets
without requiring Cellar credentials; pushes to `main` use the configured
Cellar cache for the NixOS variant.
