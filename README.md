# llama.cpp for Omarchy

[![Omarchy](https://img.shields.io/badge/Omarchy-Linux-blue.svg)](https://omarchy.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20Hyprland-lightgrey.svg)]()

An Omarchy bar dropdown for [llama.cpp](https://github.com/ggml-org/llama.cpp).
Declare your models once, then pick one from the bar and start or stop it.

- 🦙 One bar icon for every local model you run.
- 📋 A dropdown lists the models from your config; click a row to start it.
- ⏹️ Click the running model again to stop it.
- 🔁 One server at a time: starting a model stops whichever one was running.
- 🖱️ Right click opens the running server's web UI.

---

## Requirements

| Dependency | Why | Notes |
|---|---|---|
| Omarchy 4 (Quattro) | Hosts the shell and bar | The widget runs inside `omarchy-shell`. |
| `jq` | Reads and validates the model registry | Required. |
| `llama` (or `llama-server`) | The server binary | Must be on `PATH`. |
| `ss` (iproute2) | Detects the server's process | Present on Arch Linux by default. |
| `setsid` (util-linux) | Starts the server in its own session | Present on Arch Linux by default. |
| `xdg-open` (optional) | Opens the web UI on right click | Skip if you never use right click. |

## Installation

### Omarchy plugin manager (recommended)

```sh
omarchy plugin add https://github.com/devmercenario/omarchy-llama-cpp.git --enable --yes
```

### Manual

1. Copy this directory to `~/.config/omarchy/plugins/devmercenario.llama-cpp/`.
2. `omarchy-shell shell rescanPlugins`
3. `omarchy plugin enable devmercenario.llama-cpp`
4. Optionally move the icon: `omarchy bar move devmercenario.llama-cpp --section right`

### The helper CLI on your `PATH`

The helper ships inside the plugin. Link it into `~/.local/bin` so the
`omarchy-llama-cpp` examples below work:

```sh
ln -s ~/.config/omarchy/plugins/devmercenario.llama-cpp/bin/omarchy-llama-cpp ~/.local/bin/omarchy-llama-cpp
```

Without the symlink, call it by its full path
(`~/.config/omarchy/plugins/devmercenario.llama-cpp/bin/omarchy-llama-cpp`).

## Configuration

Models live in `~/.config/omarchy-llama-cpp/models.json`. Until that file
exists the widget uses the bundled example, so you can try it immediately:

```sh
omarchy-llama-cpp init     # copy the bundled example to your config dir
```

Then edit the file. Every model is one entry under `models`:

```json
{
  "models": [
    {
      "id": "qwen3.8-27b",
      "name": "Qwen3.8 27B (UD-IQ4_XS)",
      "host": "127.0.0.1",
      "port": 8080,
      "command": [
        "llama", "serve",
        "-hf", "unsloth/Qwen3.8-27B-GGUF:UD-IQ4_XS",
        "--no-mmproj",
        "--ctx-size", "24576",
        "--n-gpu-layers", "99",
        "--flash-attn", "on",
        "--jinja"
      ],
      "env": { "LLAMA_ARG_THREADS": "12" }
    }
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Stable identifier used by the CLI and IPC. Required. |
| `name` | string | Label shown in the dropdown. Defaults to `id`. |
| `command` | string[] | The full command to run. Required, non-empty. |
| `host` | string | Address used for the health check and the web UI. Default `127.0.0.1`. |
| `port` | integer | HTTP port. `0` or omitted means "no port check". |
| `env` | object | Extra environment variables for the process. Optional. |
| `onStart` | string[][] | Commands run before the server starts. Optional. |
| `onExit` | string[][] | Commands run after the server exits or is stopped. Optional. |

When a model needs a resource that another process holds, `onStart` releases
it and `onExit` restores it. Each hook is a list of commands, so a model can
free the resource, wait, then start. See
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for a worked example.

The registry is plain JSON and is read fresh on every action, so you can edit
it and reopen the dropdown — no restart needed.

Validate your file after editing:

```sh
omarchy-llama-cpp validate
```

### Migrating an `llm-serve` function

A shell function that runs `llama serve …` maps directly onto one entry:
put the program first, then each argument as its own array element.

## Usage

| Action | Effect |
|---|---|
| Left click | Open the dropdown of configured models. |
| Click a row | Start that model (stopping any other), or stop it if it is the running one. |
| Right click | Open the running server's web UI. |

Shell IPC:

```sh
omarchy-shell shell call devmercenario.llama-cpp toggle ''
omarchy-shell shell call devmercenario.llama-cpp refresh ''
```

Helper CLI:

```sh
omarchy-llama-cpp list                 # configured models and their state
omarchy-llama-cpp status --json        # what is running right now
omarchy-llama-cpp start  qwen3.8-27b
omarchy-llama-cpp toggle qwen3.8-27b
omarchy-llama-cpp stop
omarchy-llama-cpp open                 # open the running server
omarchy-llama-cpp logs qwen3.8-27b     # path to that model's log
```

## Settings

Configured per widget in `~/.config/omarchy/shell.json`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `refreshIntervalSec` | integer | `4` | How often the widget polls the server state. |
| `idleOpacity` | number | `0.35` | Icon opacity while no server is running. |
| `glyph` | string | `""` | Optional Nerd Font glyph instead of the bundled icon. |

## How it works

`BarWidget.qml` polls `omarchy-llama-cpp status --json` and paints the icon.
`Panel.qml` is the dropdown: it lists `omarchy-llama-cpp list --json` and
calls `toggle <id>` per row. All process handling lives in the helper:

- Runtime state (PID and process group) lives in an owner-only directory
  under `$XDG_RUNTIME_DIR`, never a shared temporary path.
- `start` runs the command in a **new session**, so `stop` signals the whole
  process group without touching anything else.
- `stop` verifies the target is a live, same-user process whose argv names the
  configured launcher before signaling it, then waits and falls back to
  `SIGKILL`.
- The server log for each model is kept at
  `$XDG_STATE_HOME/omarchy-llama-cpp/<id>.log`.
- If a start fails, the dropdown marks that model with a red dot and shows the
  last error line from its log, so a model that cannot load (bad flags, no
  free VRAM) says so instead of silently reverting to stopped.

## Removal

```sh
omarchy plugin remove devmercenario.llama-cpp --yes
rm -f ~/.local/bin/omarchy-llama-cpp   # if you created the symlink
```

Your `~/.config/omarchy-llama-cpp/models.json` is left untouched; delete it
manually if you no longer need it.

## Icon

`assets/llama.svg` is the **official llama.cpp logo**, used to identify the
llama.cpp service this plugin controls. The llama.cpp name and logo belong to
the llama.cpp project; this plugin is an independent community project and is
not affiliated with or endorsed by it. Set the `glyph` setting if you prefer a
Nerd Font glyph.

## License

MIT — see [LICENSE](LICENSE). Independent community plugin, not affiliated
with or endorsed by the llama.cpp project.
