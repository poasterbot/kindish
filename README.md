# Kindish — full-system KindleOS 5.19.2 VM

Kindish boots Amazon's signed 2024 Kindle Basic (KT6/Bellatrix) 5.19.2
root filesystem as a complete ARM virtual machine. The kernel invokes
Amazon's `/sbin/init` wrapper, which execs `/sbin/init.exe` as PID 1; the stock
Upstart graph mounts the Kindle partition layout, and the real Xorg, Java
framework, KAF/KPP UI, `wifid`, `wpa_supplicant`, and `tizen-mtp` processes run
inside the guest.

The retail MT8110 kernel cannot boot QEMU's generic ARM machine. Kindish uses
a pinned Linux 6.12 compatibility kernel for QEMU `virt`, while retaining the
official Amazon userspace and init system. Narrow compatibility patches cover
only hardware ABI edges that QEMU does not implement.

## Quick start on Ubuntu 24.04

```bash
curl https://mise.run | sh
eval "$(~/.local/bin/mise activate bash)"
mise trust
mise run setup
mise run start
```

Open the URL printed by `start`, normally:

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale
```

The first run downloads and verifies the official OTA, builds the ARM kernel,
and creates a persistent 4 GiB virtual SD card under `.cache/runtime/`. Initial
Java startup can take several minutes under TCG translation. Stop it with:

```bash
mise run stop
```

`stop` asks the real Kindle shutdown job to halt and preserves the writable
`/var/local` and userstore partitions.

## Emulated hardware

- Storage: QEMU SDHCI with a Kindle-shaped ten-partition GPT image. The
  official root filesystem is partition 8; stock first-boot jobs own the
  writable partitions.
- Display: `virtio-gpu` provides a 1072×1448 DRM framebuffer with the
  91×123 mm, 300 ppi panel metrics expected by KindleOS. Amazon Xorg 1.8 and
  its `mtk_drv.so` render the actual Kindle UI into `/dev/fb0`. A narrow
  device-capability interposer supplies those same metrics to Amazon Java,
  WebKit, and window-manager code while forwarding every other capability to
  the stock library.
- Input: QEMU virtio keyboard and direct multi-touch devices. The touch device
  passes through Amazon's `multitouch.so` GestureEngine so browser contacts
  become normal Kindle taps and swipes.
- Network: `mac80211_hwsim` creates two real `nl80211` radios. Stock `wifid`
  owns `wlan0`; ARM `hostapd` turns `wlan1` into the `Kindish Internet` access
  point in a separate Linux network namespace. DHCP and a two-stage AP/uplink
  NAT route packets through the radio and then a separate virtio Ethernet
  uplink, so KindleOS cannot accidentally route around the emulated adapter.
- USB: the guest's `dummy_hcd` connects Amazon's FunctionFS MTP gadget to an
  in-guest USB host. USB/IP exports that exact device to the Linux host. The
  virtual cable controller is loaded only by `mtp:start`, preventing a
  permanent "Connected to computer" blanket during normal boots.

The compatibility kernel also supplies Kindle board identity nodes such as
`/proc/board_id`, `/proc/product_name`, `/proc/productid`, and `/proc/usid`.
Without `/proc/usid`, the stock Wi-Fi and MTP daemons deliberately exit.

## Wi-Fi

The guest access point is open and uses `10.177.0.0/24`. It is simulator
plumbing, not a security boundary. KindleOS scans, associates, and obtains a
lease over `wlan0` exactly as it would with a physical adapter; Internet
traffic then traverses the second emulated radio, an isolated AP namespace,
and QEMU's private uplink. The AP namespace translates station addresses onto
its veth, and a marked policy route keeps that uplink traffic on `eth0` even
when stock `wifid` installs more-specific DNS routes on `wlan0`.

QEMU's VNC, noVNC, SSH forwarding, and USB/IP forwarding listen on loopback
only. No account credentials are included in the image.

## MTP

With the VM running:

```bash
mise run mtp:start
lsusb -d 1949:9981
mtp-detect
mise run mtp:stop
```

The attached device is Amazon VID/PID `1949:9981`. `mtp-detect` talks to the
OTA's real `/usr/bin/tizen-mtp` responder and can open a session, enumerate its
operations, and access the persistent Kindle storage. The host requires the
running kernel's `vhci_hcd` module; `mise run setup` installs Ubuntu's matching
`linux-modules-extra` and `linux-tools` packages.

## Compatibility boundaries

The root filesystem remains overwhelmingly stock. Maintained patches:

- guard writes to MT8110-only `/proc/bd` diagnostics;
- use static board capabilities where the MediaTek data-layer service is
  absent;
- generate Xorg configuration for virtio graphics and input;
- translate VNC's primary pointer contact into QEMU's native multi-touch event
  stream;
- extend the framework-start watchdog from 105 to 600 seconds for TCG;
- add a root diagnostic console, the in-guest Wi-Fi AP, and the USB/IP bridge.

The kernel no-ops only the private e-ink ioctls issued by the old MediaTek X
driver when the active framebuffer is `virtio_gpu`. It also preserves the
active USB configuration only while the emulated Kindle `1949:9981` device on
`dummy_hcd` changes ownership from Linux's generic USB driver to
`usbip-host`; without that narrow exception, the loopback controller turns a
host-driver handoff into a false physical unplug. Actual pixels still flow
through DRM/fbdev, input through Linux evdev and Kindle's GestureEngine, and
MTP requests through the OTA's responder.

## Useful commands

```bash
mise run fetch
mise run extract
mise run inspect
mise run status
mise run check
```

The serial boot log is `.cache/runtime/kindish-vm-console.log`. The QMP and
diagnostic virtio-console sockets are in the same runtime directory.

## Limitations

Kindish emulates the platform contract needed by KindleOS; it is not a
cycle-accurate MT8110 model. Secure boot/TEE, the physical e-ink waveform
controller, battery/thermal sensors, Bluetooth, and cellular hardware are not
emulated. Their stock services may log missing-device warnings without
blocking the main Kindle init graph.

The official OTA is generic and does not contain the Amazon-issued per-device
DSN, device secret, private key, or X.509 certificate provisioned at the
factory. Internet connectivity works, but Amazon account registration cannot
authenticate this unprovisioned virtual device: the identity service returns
HTTP 401 and KindleOS presents that device-authentication failure as a generic
"account does not exist" message. Supplying or fabricating Amazon device
credentials is intentionally outside Kindish's compatibility layer.
