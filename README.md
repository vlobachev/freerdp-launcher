# FreeRDP Launcher

A tiny native macOS GUI front-end and connection manager for
[FreeRDP](https://www.freerdp.com/) (`sdl-freerdp`).

## Why

Microsoft's **Windows App** / **Remote Desktop** client on macOS fails NLA
authentication against some RDP servers — most notably
[`gnome-remote-desktop`](https://gitlab.gnome.org/GNOME/gnome-remote-desktop),
which returns **error 0x207** (NTLM "Message Integrity Check" failure).
**FreeRDP** authenticates correctly against those same servers, but on macOS it
ships only a command-line client (`sdl-freerdp`).

This app wraps `sdl-freerdp` in a clickable connection manager: pick a saved
connection, type the password, and the FreeRDP window opens. No 14-day trials,
no Microsoft client, just a small AppleScript app over the binary you already
have from Homebrew.

## Requirements

- macOS
- [Homebrew](https://brew.sh) FreeRDP:
  ```sh
  brew install freerdp
  ```

## Install

```sh
git clone https://github.com/<you>/freerdp-launcher.git
cd freerdp-launcher
./build.sh                 # builds & installs to /Applications
# or install elsewhere:
./build.sh ~/Applications
```

Then launch **FreeRDP Launcher** from Spotlight / Launchpad / the Dock.

## Usage

1. Launch the app.
2. First run: choose **“+ Add connection…”** and enter a name, host, username,
   and (optionally) extra FreeRDP flags.
3. Pick a saved connection, type the password (hidden, never stored), choose
   **Window** or **Fullscreen**, and connect.

In fullscreen, **Ctrl + Alt + Enter** toggles back to a window.

## Connection profiles

Profiles are stored in a plain TAB-separated file you can also edit by hand
(the app's **“✎ Edit connections file…”** entry opens it):

```
~/.config/freerdp-launcher/connections.tsv
```

Format — one connection per line, fields separated by a TAB; lines starting
with `#` are ignored:

```
name<TAB>host<TAB>user<TAB>extra_flags
```

Example:

```
Work desktop	10.0.0.50	alice	/sound:sys:mac
Home GNOME box	gnomebox.lan	bob	+microphone
```

`extra_flags` is passed verbatim to `sdl-freerdp`, so anything from
`sdl-freerdp /help` works (audio, drives, gateway, etc.).

No hosts, usernames, or passwords are baked into the app — everything lives in
your local config file, and passwords are only ever typed at connect time.

## How it works

The app is a small AppleScript that:

1. locates `sdl-freerdp` (falls back to `sdl-freerdp3` / `xfreerdp`),
2. reads connection profiles from `connections.tsv`,
3. shows native macOS dialogs to pick a connection and enter the password,
4. launches `sdl-freerdp` detached with sensible defaults
   (`/cert:ignore`, clipboard, dynamic resolution, audio).

See [`src/FreeRDP Launcher.applescript`](src/FreeRDP%20Launcher.applescript).

## License

[MIT](LICENSE)
