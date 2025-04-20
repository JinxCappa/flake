#!/bin/sh
set -eu

hostname="$1"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_file() {
	owner="$1"
	mode="$2"
	path="$3"
	mkdir -p "$(dirname "$path")"
	cat > "$path"
	chown "$owner" "$path"
	chmod "$mode" "$path"
}

rc_add() {
	mkdir -p "$tmp/etc/runlevels/$2"
	ln -s "/etc/init.d/$1" "$tmp/etc/runlevels/$2/$1"
}

make_file root:root 0644 "$tmp/etc/hostname" <<EOF
$hostname
EOF

make_file root:root 0644 "$tmp/etc/apk/world" <<'EOF'
alpine-base
bash
dhcpcd
dhcpcd-openrc
iproute2
kexec-tools
openssh
sudo
util-linux
EOF

make_file root:root 0644 "$tmp/etc/conf.d/dhcpcd" <<'EOF'
# A link-local 169.254/16 address cannot support this installer. Keep retrying
# DHCP instead of allowing dhcpcd's IPv4LL fallback.
command_args="-L"
EOF

make_file root:root 0440 "$tmp/etc/sudoers.d/nixos" <<'EOF'
nixos ALL=(ALL:ALL) NOPASSWD: ALL
EOF

make_file root:root 0600 "$tmp/etc/bootstrap/authorized_keys" \
	< /root/.mkimage/authorized_keys

make_file root:root 0644 "$tmp/etc/ssh/sshd_config" <<'EOF'
Port 22
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
AuthorizedKeysFile .ssh/authorized_keys
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AllowUsers nixos
PrintMotd no
Subsystem sftp internal-sftp
EOF

make_file root:root 0644 "$tmp/etc/inittab" <<'EOF'
# /etc/inittab

::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

# Require the public bootstrap password on local consoles. Network logins remain
# key-only through sshd_config.
tty1::respawn:/sbin/agetty --noclear --issue-file /run/bootstrap-network.issue tty1 38400 linux
tty2::respawn:/sbin/agetty --noclear --issue-file /run/bootstrap-network.issue tty2 38400 linux
tty3::respawn:/sbin/agetty --noclear --issue-file /run/bootstrap-network.issue tty3 38400 linux
tty4::respawn:/sbin/agetty --noclear --issue-file /run/bootstrap-network.issue tty4 38400 linux
tty5::respawn:/sbin/agetty --noclear --issue-file /run/bootstrap-network.issue tty5 38400 linux
tty6::respawn:/sbin/agetty --noclear --issue-file /run/bootstrap-network.issue tty6 38400 linux

# Put a getty on the serial port.
#ttyS0::respawn:/sbin/agetty --noclear --issue-file /run/bootstrap-network.issue -L ttyS0 115200 vt100

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

make_file root:root 0755 "$tmp/etc/init.d/bootstrap-user" <<'EOF'
#!/sbin/openrc-run

description="Create the nixos bootstrap user"

depend() {
	need localmount
	before sshd
}

start() {
	ebegin "Creating nixos bootstrap user"
	if ! id nixos >/dev/null 2>&1; then
		adduser -D -u 1000 -h /home/nixos -s /bin/ash nixos
		addgroup nixos wheel
	fi
	# A locked shadow entry makes non-PAM OpenSSH reject the account before it
	# checks authorized_keys. Keep SSH key-only, but give recovery consoles the
	# same public bootstrap password as the NixOS installer assets.
	printf '%s\n' 'nixos:nixos' | chpasswd
	install -d -m 0700 -o nixos -g nixos /home/nixos/.ssh
	install -m 0600 -o nixos -g nixos \
		/etc/bootstrap/authorized_keys /home/nixos/.ssh/authorized_keys
	eend $?
}
EOF

make_file root:root 0755 "$tmp/etc/init.d/bootstrap-console" <<'EOF'
#!/sbin/openrc-run

description="Show bootstrap network information on local consoles"

depend() {
	need dhcpcd
	after bootstrap-user
}

start() {
	ebegin "Waiting for a usable DHCP IPv4 address"
	until ip -o -4 address show scope global 2>/dev/null \
		| awk '$4 !~ /^169[.]254[.]/ { found = 1 } END { exit !found }'
	do
		sleep 1
	done
	eend 0

	ebegin "Generating bootstrap network information"

	message=/run/bootstrap-network.issue

	{
		echo
		echo "nixos-anywhere installer network:"

		for iface_path in /sys/class/net/*; do
			interface="$(basename "$iface_path")"
			if [ "$interface" = "lo" ]; then
				continue
			fi

			mac="$(cat "$iface_path/address")"
			ipv4="$(ip -o -4 address show dev "$interface" scope global 2>/dev/null \
				| awk '$4 !~ /^169[.]254[.]/ { printf "%s%s", separator, $4; separator = ", " }')"
			ipv6="$(ip -o -6 address show dev "$interface" scope global 2>/dev/null \
				| awk '{ printf "%s%s", separator, $4; separator = ", " }')"

			[ -n "$ipv4" ] || ipv4="not acquired"
			[ -n "$ipv6" ] || ipv6="not acquired"

			printf '  %s\n    IPv4: %s\n    IPv6: %s\n    MAC:  %s\n' \
				"$interface" "$ipv4" "$ipv6" "$mac"
		done

		echo
		echo "Local login: nixos / nixos"
		echo "SSH login:   nixos@<IPv4 address> (SSH key required)"
		echo
	} > "$message"

	# agetty reads the runtime issue file before each local login prompt.
	install -m 0644 "$message" /etc/issue

	eend $?
}
EOF

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add bootstrap-user boot

rc_add dhcpcd default
rc_add bootstrap-console default
rc_add sshd default

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

tar -C "$tmp" --owner=0 --group=0 -czf "$hostname.apkovl.tar.gz" etc
