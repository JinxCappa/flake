profile_bootstrap() {
	profile_standard
	profile_abbrev="bootstrap"
	title="NixOS Anywhere Bootstrap"
	desc="Headless Alpine bootstrap environment for nixos-anywhere."
	arch="x86_64"
	hostname="bootstrap"
	image_name="bootstrap-alpine"
	output_filename="bootstrap-alpine-${RELEASE}-${ARCH}.iso"
	apkovl="genapkovl-bootstrap.sh"
	apks="$apks bash iproute2 kexec-tools sudo util-linux"
	# Alpine patches its LTS kernel to disable kexec_load by default. This image
	# exists specifically to hand off to nixos-anywhere through kexec.
	kernel_cmdline="$kernel_cmdline kexec_load_disabled=0"
}
