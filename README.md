# FreeRDP Launcher

A small native **SwiftUI** macOS app — a connection manager that launches
[FreeRDP](https://www.freerdp.com/) (`sdl-freerdp`) sessions.

## Why

Microsoft's **Windows App** / **Remote Desktop** client on macOS fails NLA
authentication against some RDP servers — most notably
[`gnome-remote-desktop`](https://gitlab.gnome.org/GNOME/gnome-remote-desktop)
(**error 0x207**, NTLM "Message Integrity Check" failure). **FreeRDP**
authenticates correctly, but on macOS it ships only a command-line client.

FreeRDP Launcher gives that client a proper home: a persistent window with a
sidebar of saved connections, inline add/edit, passwords in the macOS Keychain,
and one-click connect. No 14-day trials, no Microsoft client.

## Features

- Native macOS app (SwiftUI), single persistent manager window.
- Saved connections with sidebar + detail layout; inline add/edit (no modal chains).
- Passwords stored in the **macOS Keychain**, never in plaintext.
- Password is passed to FreeRDP via `/args-from:stdin`, so it never appears in
  `ps` / the process list.
- First-class **resolution & scaling** controls (the usual pain point on Retina).
- Launch multiple sessions; the manager stays open.
- Graceful "FreeRDP not installed" handling.

## Requirements

- macOS 14 (Sonoma) or later
- [Homebrew](https://brew.sh) FreeRDP: `brew install freerdp`
- To build: the Swift toolchain (Xcode **or** the Command Line Tools — `swift` on `PATH`)

## Build & install

```sh
git clone https://github.com/vlobachev/freerdp-launcher.git
cd freerdp-launcher
./build.sh /Applications      # builds and installs "FreeRDP Launcher.app"
# or just build into ./dist:
./build.sh
```

It's an unsigned local build, so on first launch macOS Gatekeeper may complain —
right-click the app → **Open**, or run
`xattr -dr com.apple.quarantine "/Applications/FreeRDP Launcher.app"`.

## Usage

1. Launch **FreeRDP Launcher**.
2. Click **+**, fill in Name / Host / Username / Password and the Display options,
   **Save**.
3. Select the connection and hit **Connect** (or press ⏎). The remote desktop
   opens in FreeRDP's own window; the manager stays open.

In fullscreen, **Ctrl + Alt + Enter** toggles back to a window.

## Getting crisp, large text (Retina)

The remote desktop looks blurry/small when the server renders at a low
resolution and macOS upscales it on a Retina display. The fix is two-sided:

1. **Client (this app):** set the connection's resolution to your Mac's *native*
   pixel size (e.g. `2560 × 1600`) so FreeRDP carries pixels 1:1 — no upscaling.
2. **Server (GNOME):** make the UI physically larger by scaling GNOME, which
   renders text as crisp vectors. On the remote machine, as your user:
   ```sh
   gsettings set org.gnome.desktop.interface scaling-factor 2
   # optional finer text bump:
   gsettings set org.gnome.desktop.interface text-scaling-factor 1.1
   ```

Prefer **server-side** (GNOME) scaling over client-side stretching for the
sharpest result; don't do both at once.

## Connection storage

- Connections: `~/Library/Application Support/FreeRDP Launcher/connections.json`
  (no passwords — those live in the Keychain).
- On first run the app imports any legacy
  `~/.config/freerdp-launcher/connections.tsv` from earlier versions.

## How it works

The app is a SwiftUI connection manager. It does **not** re-implement RDP
rendering — that's `sdl-freerdp`'s job. The app finds the FreeRDP binary
(`/opt/homebrew/bin/sdl-freerdp` and friends), builds the argument list from the
connection's settings, and spawns it detached, feeding all arguments (including
the password) through `/args-from:stdin`.

See [`docs/`](docs/) for the architecture notes.

## License

[MIT](LICENSE)
