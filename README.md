# Omaports

Find open TCP ports and close them from the Omarchy bar and a Raycast-style overlay.

## Install

```sh
omarchy plugin add https://github.com/yuler/omaports.git --enable
```

Local checkout (symlink, so edits reload without copying):

```sh
make link enable
```

That replaces a previously copied `~/.config/omarchy/plugins/yuler.omaports` with a symlink to this repo. Saved QML/JS reloads in the shell automatically.

`omarchy plugin validate` refuses a plugin *path* that is itself a symlink (it walks `-type l`). `make validate` therefore checks this checkout, which is a real directory. `omarchy plugin add` still installs a normal clone.

```sh
make test       # Model.js unit tests
make validate   # tests + omarchy plugin validate
make unlink     # remove the symlink only
```

Summon the overlay:

```sh
omarchy-shell shell toggle yuler.omaports
```

Suggested Hyprland binding (`~/.config/hypr/bindings.lua`):

```lua
o.bind("SUPER + ALT + P", "Omaports", "omarchy-shell shell toggle yuler.omaports")
```

## Usage

- **Bar**: left click opens the port list. Right click refreshes. The icon turns urgent when a listener is bound beyond loopback.
- **Overlay commands**: Open Ports, Kill Process Listening on, Named Ports.
- **Enter** opens `http(s)://localhost:<port>`.
- **Ctrl+Y** copies the URL.
- **Ctrl+T** opens a terminal in the process working directory.
- **Ctrl+X** kills after a confirmation dialog (or `docker stop` for published container ports).
- **Ctrl+R** (overlay) reveals the executable.
- Named Ports: type `3000=Next.js` and press Enter. Names live in `~/.local/state/omarchy/omaports/names.json`.

Kill always asks first. Only the current user's processes are signaled, after checking `/proc` uid and start time. Docker stop runs only when you already have permission to talk to the daemon.

## Configure

Bar settings expose kill signal (TERM/KILL), Docker, UDP, ignored ports, HTTPS ports, and refresh interval.

## Remove

```sh
omarchy plugin remove yuler.omaports
```

## Dependencies

- `ss` (iproute2) — required
- `docker` — optional, for published container ports
- `xdg-open`, `wl-copy`, `xdg-terminal-exec` — optional actions
