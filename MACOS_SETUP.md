# Running Kindish on Apple Silicon macOS

Kindish itself was not modified. Because it expects Ubuntu features such as loop
devices and Linux filesystem tooling, it runs inside a small ARM64 Ubuntu VM;
macOS forwards the noVNC port and Tailscale publishes it privately.

## One-time setup

Install Lima, then create an Ubuntu 24.04 VM. This machine used 8 CPUs, 12 GiB
RAM, a 50 GiB disk, and a static host-to-guest forward for noVNC:

```bash
brew install lima
limactl start --name=kindish --cpus=8 --memory=12 --disk=50 \
  --mount-none --port-forward=6080:6080,static=true \
  --vm-type=vz --yes template:ubuntu-24.04
```

Copy this repository onto the VM's local disk (compiling there is much faster
than compiling through a shared macOS mount):

```bash
guest_home="$(limactl shell kindish -- sh -lc 'printf %s "$HOME"')"
limactl copy --recursive /absolute/path/to/kindish "kindish:${guest_home}/"
```

Install the Ubuntu dependencies. `python3-venv` and `libssl-dev` are needed by
the pinned QEMU and Linux builds in addition to the packages in `mise.toml`:

```bash
limactl shell kindish -- bash -lc '
  sudo apt-get update &&
  sudo apt-get install -y \
    bc bison build-essential ca-certificates curl e2fsprogs file flex \
    gcc-arm-linux-gnueabihf git iproute2 iw libarchive-dev libelf-dev \
    libfdt-dev libglib2.0-dev libpixman-1-dev libslirp-dev libssl-dev \
    make mtp-tools ninja-build novnc patch pkg-config python3-venv \
    qemu-system-arm ripgrep rsync socat u-boot-tools usbutils util-linux \
    websockify xz-utils
'
```

## Start and expose it

The first start downloads the official Kindle firmware and builds the patched
kernel and QEMU. Later starts reuse the cache:

```bash
limactl shell kindish -- bash -lc '
  cd "$HOME/kindish" && sudo ./kindish start
'
```

Publish noVNC on the current tailnet. HTTPS is the normal link; the TCP mapping
provides an IP-based fallback when MagicDNS is not working on a client:

```bash
tailscale serve --bg --yes http://127.0.0.1:6080
tailscale serve --bg --yes --tcp=6080 tcp://127.0.0.1:6080
tailscale serve status
```

Open either:

```text
https://<tailscale-dns-name>/vnc.html?autoconnect=1&resize=scale
http://<tailscale-ip>:6080/vnc.html?autoconnect=1&resize=scale
```

Both routes are tailnet-only. Tailscale Funnel was intentionally left disabled.

## Operations

Check status:

```bash
limactl list
limactl shell kindish -- bash -lc '
  cd "$HOME/kindish" && sudo ./kindish status
'
tailscale serve status
```

If noVNC says `Display output is not active`, try the emulated power button:

```bash
limactl shell kindish -- bash -lc '
  cd "$HOME/kindish" && sudo ./scripts/power-button.sh
'
```

If the scanout remains inactive, cleanly restart Kindish; writable Kindle
storage is preserved:

```bash
limactl shell kindish -- bash -lc '
  cd "$HOME/kindish" && sudo ./kindish stop && sudo ./kindish start
'
```

After a restart, the framebuffer appears first; the Kindle Java UI may take a
minute or two to finish initializing.
