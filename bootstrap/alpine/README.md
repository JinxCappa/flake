# Alpine bootstrap image

This builds a headless x86_64 Alpine ISO and matching iPXE assets for
`nixos-anywhere`. It boots with wired DHCP, creates a `nixos` user with the
public local-console password `nixos`, installs the repository bootstrap SSH
keys, includes Bash and the other nixos-anywhere target utilities, enables
passwordless `sudo`, and displays per-interface IPv4, IPv6, and MAC information
before the local login prompt. SSH remains key-only.

IPv4 link-local fallback is disabled. Boot waits for a non-`169.254/16` DHCPv4
lease before displaying the login prompt, because this environment is only
useful once nixos-anywhere can reach it over the network.

The ISO and iPXE kernel command lines set `kexec_load_disabled=0`. Alpine's LTS
kernel otherwise rejects nixos-anywhere's kexec handoff with `EPERM` even though
the kernel was compiled with kexec support.

Build it from the repository root:

```sh
just bootstrap-alpine
```

The ISO and checksums are copied to `result/bootstrap-alpine/`. The relocatable
iPXE bundle is copied to `result/bootstrap-alpine/ipxe/` and contains
`boot.ipxe`, the kernel, initramfs, modloop, bootstrap overlay, and checksums.

Serve the `ipxe/` directory over HTTP and chain its script:

```ipxe
chain http://<server>/bootstrap-alpine/boot.ipxe
```

The script uses iPXE's current working URI, so the directory can be hosted at
any HTTP URL without editing `boot.ipxe`.

The **Installer assets** GitHub Actions workflow also builds and publishes the
ISO as `alpine-installer-iso` and the iPXE directory as the separate
`alpine-installer-netboot` artifact.

Connect and install with:

```sh
ssh nixos@<ip>
nix run github:nix-community/nixos-anywhere -- \
  --flake .#<host> --target-host nixos@<ip>
```
