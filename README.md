# Kindish — KT6 KindleOS 5.19.2 simulator

Kindish downloads Amazon's signed **2024 Kindle Basic (KT6/Bellatrix) 5.19.2**
recovery OTA, verifies a pinned SHA-256, extracts its ARMv7 root filesystem,
and runs the real Kindle userspace under QEMU user-mode translation. The real
OTA X server, MediaTek display driver, Kindle multitouch driver, Java
framework, KAF, Home/Library application, app manager, KPP process, and MTP
responder all run in the simulator.

It provides an interactive 1072×1448 screen in a local browser, starts at
Home without the login/OOBE gate, has no host or Internet network path, and
can appear to Linux as a virtual USB Kindle with read/write MTP storage.

## Quick start (Ubuntu 24.04)

```bash
curl https://mise.run | sh
eval "$(~/.local/bin/mise activate bash)"
mise trust
mise bootstrap --yes
mise run start
```

The committed `mise.toml` pins Python, declares the Ubuntu package set, builds
the running kernel's virtual USB module, and provides all project tasks. After
the first bootstrap, use `mise tasks` to list them.

Open the URL printed by `start`, normally:

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale
```

The first run downloads roughly 357 MiB and builds a persistent runtime under
`.cache/`. Mouse input goes through a host `uinput` absolute-touch device and
the OTA's `/usr/lib/xorg/modules/input/multitouch.so`; it is not translated
into application-level clicks. noVNC and VNC listen on loopback only.

```bash
mise run stop
```

Books placed in `.cache/userstore/` persist and are visible at `/mnt/us` and
`/mnt/base-us` in KindleOS.

## Virtual USB MTP

With KindleOS running:

```bash
mise run mtp:start
lsusb -d 1949:9981
mtp-detect
mise run mtp:stop
```

This uses Linux `dummy_hcd` as a virtual host controller and UDC, ConfigFS plus
FunctionFS for the USB transport, and the **actual OTA
`/usr/bin/tizen-mtp`** as the protocol responder. It enumerates with Amazon
VID/PID `1949:9981`, reports itself as an Amazon Kindle, opens MTP sessions,
and exposes read/write Internal Storage. It is not a filesystem-only MTP
facade.

Amazon's `volumd` normally advances MTP after a physical MT8110 USB interrupt
and temporarily unmounts `/mnt/us`. Kindish keeps the shared userstore mounted
and emits that single `driveModeStateChanged=ON` hardware-completion event;
all USB descriptors and MTP request handling still come from Amazon's
responder.

Ubuntu does not normally ship `dummy_hcd.ko`. `kindish setup` downloads the
Linux v6.8 `dummy_hcd.c` from the upstream kernel repository, verifies its
pinned hash, and builds it against the running Ubuntu kernel headers. This is
an unsigned out-of-tree module and taints the host kernel; Secure Boot module
enforcement may reject it.

## Display and e-ink model

This is more than a UI reimplementation. The OTA's ARM `/usr/bin/Xorg` 1.8.2
loads its real `mtk_drv.so`, detects an emulated 1072×1448, 8-bit StaticGray
`/dev/fb0`, and renders the real Kindle windows. A narrow preload shim supplies
the framebuffer geometry and missing Lab126 identity/block-device ioctls. The
framebuffer is presented through x11vnc/noVNC rather than a physical waveform
controller.

The OTA's Awesome/window-manager binary can run, but its rotation policy
assumes MT8110 framebuffer rotation and distorts dialogs without that kernel
interface. Kindish therefore uses a small host-side layout watcher: the active
real Kindle booklet occupies the center of the panel while the OTA's own KPP
top chrome and Home/Library bottom navigation retain their native dimensions.
E-ink ghosting, waveform timing, power states, secure boot/TEE, and the
MediaTek display controller are not modeled.

## Login bypass and offline boundary

Kindish seeds the real Home preferences so first-boot/OOBE tutorials are
complete and applies the maintained KPP registration-detection patch to a
runtime copy of KPP Hermes bytecode. It does not create Amazon credentials:
the actual registration service remains honestly unregistered, and Library
may show “Set Up Your Kindle,” but Home and local content are usable without a
login. The downloaded OTA and extracted lower image remain unchanged.

The Kindle process tree runs in fresh network and IPC namespaces. Its network
namespace contains only loopback—no veth, external route, DNS, NAT, host path,
or Internet path. Browser/VNC and virtual USB live outside that namespace on
the host.

## Scope and limitations

The OTA also contains Amazon's ARM FIT kernel, ramdisk, and MT8110 device tree,
and `./kindish inspect` preserves and reports them. QEMU has no KT6/MT8110
machine model, so that kernel cannot be honestly booted as a full-system VM.
Kindish runs the actual operating-system userspace with emulated devices under
it; it is not cycle-accurate hardware emulation.

Useful commands:

```bash
mise run fetch        # official OTA and exact hash verification
mise run extract      # KindleTool extraction
mise run inspect      # OTA, FIT kernel, and filesystem metadata
mise run status
mise run check        # shell, Python, C, and whitespace validation
```

Host-side logs are in `.cache/runtime/logs/`; Kindle-side logs live in the
persistent runtime image. Do not add interfaces to the Kindle network
namespace or externally expose the loopback-only VNC ports if isolation is a
requirement.
