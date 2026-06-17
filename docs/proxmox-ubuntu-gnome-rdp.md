# GPU-accelerated GNOME over RDP on Proxmox (Ubuntu LXC)

A field guide to running a **real GNOME desktop** inside a Proxmox **LXC
container** and reaching it from a Mac with **FreeRDP Launcher**, with
**hardware (GPU) acceleration**.

This is the configuration this app was built for. It is finicky: GNOME is
Wayland-only on recent Ubuntu, `gnome-remote-desktop` (grd) has hard
requirements, and an unprivileged LXC blocks several things grd needs. Every
wall below was hit in practice — the guide is the set of fixes that make it
work end to end.

> Replace every `<PLACEHOLDER>` with your own value. Nothing here contains real
> hosts, IPs, or credentials.

---

## Why an LXC (and not a VM)

A KVM **VM** can run GNOME via grd out of the box, but without GPU passthrough
it renders in **software** (llvmpipe). Scrolling and video are sluggish because
the CPU both draws every frame *and* encodes the RDP video stream.

An **LXC container** shares the host kernel, so the host iGPU/GPU
(`/dev/dri/renderD128`) can be handed to it cheaply. grd then renders with the
GPU **and** encodes H.264 on the GPU (via Vulkan). That is the difference
between "laggy" and "smooth". The cost: an LXC needs extra configuration that a
VM does not — that's the rest of this document.

---

## The short version (TL;DR)

On the **Proxmox host**, the container config (`/etc/pve/lxc/<CTID>.conf`) needs:

```ini
unprivileged: 1
features: nesting=1,keyctl=1,fuse=1
lxc.apparmor.profile: unconfined
# GPU passthrough (adjust the render node minor numbers to your host):
dev0: /dev/dri/card0,gid=44
dev1: /dev/dri/renderD128,gid=104
```

Inside the **container**:

- Install GNOME + `gnome-remote-desktop` + **gdm3**.
- Make **gdm3** the display manager (NOT lightdm). grd's remote-login backend
  will not even bind its RDP port without gdm running.
- Configure grd in **system** mode (file-based credentials, no keyring).

On the **client**:

- Use **FreeRDP** (`sdl-freerdp`), not Microsoft's client.
- Set the graphics codec to **H.264 AVC 4:2:0** to engage the GPU encoder.

If you skip any of these, you get one of the failure modes in
[Gotchas](#gotchas-the-walls-and-the-fixes).

---

## Step 1 — Create the container (Proxmox host)

A normal unprivileged Ubuntu LXC. Example with `pct`:

```sh
pct create <CTID> <STORAGE>:vztmpl/ubuntu-<VERSION>-standard_*.tar.zst \
  --hostname desktop \
  --ostype ubuntu \
  --cores 4 --memory 8192 --swap 2048 \
  --rootfs <STORAGE>:32 \
  --net0 name=eth0,bridge=vmbr0,ip=<CONTAINER_IP>/24,gw=<GATEWAY>,type=veth \
  --onboot 1 \
  --unprivileged 1 \
  --features nesting=1,keyctl=1,fuse=1 \
  --ssh-public-keys <PATH_TO_YOUR_PUBKEY>
```

`fuse=1` is **not optional** — grd's clipboard mounts a FUSE filesystem and the
session daemon **aborts (SIGABRT)** if `/dev/fuse` is missing.

## Step 2 — AppArmor + GPU (Proxmox host)

Edit `/etc/pve/lxc/<CTID>.conf` and add:

```ini
lxc.apparmor.profile: unconfined
dev0: /dev/dri/card0,gid=44
dev1: /dev/dri/renderD128,gid=104
```

- **`lxc.apparmor.profile: unconfined`** — even with `fuse=1` and `/dev/fuse`
  present, the default AppArmor profile **denies `fusermount3`** from passing
  the FUSE fd over its control socket (`apparmor="DENIED" ... profile=
  "fusermount3" ... denied="send"`). The grd handover daemon then aborts. Going
  unconfined removes the confinement while keeping the container *unprivileged*
  (the user-namespace mapping is untouched) — much lighter than converting to a
  privileged container.
- **`dev0`/`dev1`** pass the GPU through. Find the right minor numbers and group
  GIDs with `ls -l /dev/dri` on the host (`card0`/`cardN`, `renderD128`). The
  `gid=` must match the in-container `video` / `render` groups (often 44/104).

Apply and reboot the container:

```sh
pct reboot <CTID>
```

Verify inside the container afterwards:

```sh
ls -l /dev/fuse            # must exist: crw-rw-rw- ... 10, 229
ls -l /dev/dri            # card0 + renderD128 present
```

## Step 3 — Install the desktop (inside the container)

```sh
apt update
apt install -y ubuntu-desktop-minimal gnome-remote-desktop gdm3
# Optional but recommended for a usable desktop:
apt install -y gnome-shell-extension-ubuntu-dock \
               gnome-shell-extension-appindicator gnome-tweaks
```

GNOME 4x+ on Ubuntu is **Wayland-only** — there is no Xorg GNOME session to
serve over a classic X11 RDP/VNC bridge. grd's Wayland headless backend is the
supported path, and it needs a real **seat** (`seat0`) and a display manager,
which is why gdm matters next.

## Step 4 — Make gdm3 the display manager (inside the container)

This is the step everyone misses. grd's **system / remote-login** backend
integrates with **gdm**. If `lightdm` (or anything else) owns the seat and gdm
is not running, `gnome-remote-desktop.service` reports `active` but **never
starts the RDP server / binds the port**.

```sh
echo "/usr/sbin/gdm3" > /etc/X11/default-display-manager
systemctl disable lightdm.service     # if present
systemctl enable gdm3.service
```

(Optional) auto-login so a local session is always present —
`/etc/gdm3/custom.conf`:

```ini
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=<USERNAME>
```

## Step 5 — Configure grd in system mode (inside the container)

System mode stores credentials in a file (`/etc/gnome-remote-desktop/`), so it
works **headless** — no login keyring to unlock (the keyring is the reason
user/headless mode fails on auto-login boxes).

```sh
# TLS cert/key (grd generates them; make sure grd owns them):
chown gnome-remote-desktop:gnome-remote-desktop \
      /etc/gnome-remote-desktop/rdp-tls.crt \
      /etc/gnome-remote-desktop/rdp-tls.key

# Credentials — pass the password on stdin, never as a CLI argument:
printf '%s' "<PASSWORD>" | grdctl --system rdp set-credentials <USERNAME>

grdctl --system rdp set-port 3389        # default; pick another to coexist with xrdp
grdctl --system rdp enable
systemctl enable --now gnome-remote-desktop.service
```

The RDP credentials are **separate** from the Unix login password. If you also
log in locally/auto-login, keep them in sync to avoid confusion.

Reboot once, then verify:

```sh
systemctl is-active gdm gnome-remote-desktop.service     # both active
ss -ltnp | grep :3389                                    # grd is LISTENING
loginctl list-seats                                      # seat0 present
```

## Step 6 — Connect from the client

Use **FreeRDP Launcher** (this app) or `sdl-freerdp` directly:

- **Host** `<CONTAINER_IP>`, **Port** `3389`, **User** `<USERNAME>`.
- **Display:** Dynamic (resizable) is the smoothest.
- **Graphics codec:** **H.264 AVC 4:2:0** — this is what routes encoding through
  the GPU. On *Automatic* the negotiated path may encode on the CPU and you lose
  most of the GPU benefit.
- **Audio:** "Play on this Mac"; bump the **Audio buffer** if sound stutters on a
  tunneled/VPN link.

On first login the desktop looks bare (just the top bar) — that is stock GNOME.
Press **Super** / use the top-left hot-corner for the Activities overview, or
enable the **Ubuntu Dock** extension for a permanent dock.

---

## Gotchas (the walls, and the fixes)

| Symptom | Cause | Fix |
|---|---|---|
| Microsoft "Windows App" / Remote Desktop fails with **error 0x207** (MIC check) | grd's NLA vs the MS client's NTLM Message Integrity Check | Use **FreeRDP**; it authenticates correctly |
| Connects, then **drops instantly**, grd log shows nothing | grd is `active` but **not listening** on its port | gdm is not the display manager — see [Step 4](#step-4--make-gdm3-the-display-manager-inside-the-container) |
| Log shows `Sending server redirection` then the client drops | grd system mode **redirects** the client to a spawned login session; some clients don't follow it | FreeRDP follows redirection fine; the MS client does not |
| `gnome-remote-desktop-handover.service: ... status=6/ABRT`, `Failed to mount FUSE filesystem` | `/dev/fuse` missing in the container | `features: ...,fuse=1` + reboot ([Step 1](#step-1--create-the-container-proxmox-host)) |
| Still SIGABRT with `/dev/fuse` present; host dmesg shows `apparmor="DENIED" ... profile="fusermount3" ... denied="send"` | AppArmor blocks the FUSE fd handoff in an unprivileged LXC | `lxc.apparmor.profile: unconfined` ([Step 2](#step-2--apparmor--gpu-proxmox-host)) |
| Session works but **scrolling is no smoother than a VM** | RDP isn't using the GPU H.264 encoder | Set client codec to **AVC420** ([Step 6](#step-6--connect-from-the-client)); confirm with `cat /sys/class/drm/cardN/device/gpu_busy_percent` while interacting |
| `RDP TLS certificate and key not yet configured properly` | grd can't read its cert/key | `chown gnome-remote-desktop:` the `rdp-tls.*` files ([Step 5](#step-5--configure-grd-in-system-mode-inside-the-container)) |
| RDP login keyring won't unlock headless (user/headless grd mode) | auto-login doesn't unlock the GNOME keyring | Use grd **system** mode (file credentials) instead |
| Desktop is empty, only a clock | Stock GNOME has no dock by default | Install/enable `ubuntu-dock` + `appindicator` extensions |
| Audio stutters | Jitter on a tunneled/VPN link, or PipeWire xruns in the headless session | Increase the client audio buffer (latency); audio over tunneled RDP is inherently the weakest link |

---

## Verifying GPU acceleration

While interacting in the session, watch the GPU on the host or in the container:

```sh
# busy % should rise above idle when you scroll/drag/play video
watch -n0.5 cat /sys/class/drm/card1/device/gpu_busy_percent
```

In the grd journal you should see the hardware encoder come up:

```
[HWAccel.Vulkan] Initialization of Vulkan was successful
```

If it says it fell back to software, or `gpu_busy_percent` never moves, the GPU
passthrough ([Step 2](#step-2--apparmor--gpu-proxmox-host)) or the client codec
([Step 6](#step-6--connect-from-the-client)) is the thing to recheck.
