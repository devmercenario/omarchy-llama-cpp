# Contributing & engineering guide

> Technical notes for extending or maintaining `omarchy-llama-cpp`.
> User-facing documentation lives in the root [README](../README.md).

## Tenets

1. **English only** — code, comments, UI strings, docs, commit messages.
2. **Never edit `/usr/share/omarchy`** — package-owned, rewritten on update.
3. **Stay unprivileged** — no `sudo`, no `pkexec`, no systemd units. The widget
   runs inside `omarchy-shell` as the user.
4. **One server at a time** — starting a model stops the current one; the
   helper is the only place that decides this.
5. **Follow Omarchy conventions** — `qs.*` styling tokens and the plugin
   manifest contract.

## Layout

```
omarchy-llama-cpp/
├── manifest.json             Plugin manifest (id devmercenario.llama-cpp)
├── BarWidget.qml             Bar icon; polls state, opens the dropdown
├── Panel.qml                 The dropdown of configured models
├── assets/llama.svg          Official llama.cpp logo (white, dimmed when idle)
├── defaults/models.json      Bundled example registry
├── bin/omarchy-llama-cpp     Registry + process helper
├── tests/                    Suites, preflight, vendored baseline scanner
├── .github/workflows/        CI
└── .githooks/pre-push        Runs tests/preflight.sh before pushing
```

## Design notes

- **Config is data, not code.** Models are a JSON array of `{id, name,
  command, host, port, env}`. The helper never evaluates a shell string;
  `command` is an argument vector, so model names cannot inject shell.
- **State lives in `$XDG_RUNTIME_DIR/omarchy-llama-cpp/`** (owner-only), never
  a predictable shared temporary path.
- **One session per server.** `start` uses `setsid`; `stop` signals the
  process group, so the whole tree goes down and nothing else is affected.
- **Verify before signaling.** `stop` refuses to kill a PID whose argv does not
  name the configured launcher, so a recycled PID cannot be hit.
- **The panel is disposable.** All behaviour lives in the helper, so a widget
  reload (or a second monitor) cannot corrupt state.

## Releasing a resource another process holds

A model that needs the whole GPU can conflict with a background app that also
holds VRAM. The `onStart` and `onExit` hooks exist for exactly that: `onStart`
runs in the helper before the server is launched, `onExit` runs in the server's
process when it exits or is signalled. Both are lists of commands.

On this machine the `voxtype` dictation daemon holds ~1.5 GB, which is enough to
push the 27B model into a partial offload. The user config mirrors what
`~/.config/bash/llm.sh` does:

```json
{
  "id": "qwen3.8-27b",
  "name": "Qwen3.8 27B (UD-IQ4_XS)",
  "host": "127.0.0.1",
  "port": 8080,
  "command": [
    "llama", "serve",
    "-hf", "unsloth/Qwen3.8-27B-GGUF:UD-IQ4_XS",
    "--no-mmproj",
    "--ctx-size", "32768",
    "--n-gpu-layers", "99",
    "--flash-attn", "on",
    "--cache-type-k", "q8_0",
    "--cache-type-v", "q8_0",
    "--jinja"
  ],
  "onStart": [
    ["systemctl", "--user", "stop", "voxtype"],
    ["sleep", "3"]
  ],
  "onExit": [
    ["systemctl", "--user", "start", "voxtype"]
  ]
}
```

The `sleep 3` gives the driver time to actually release the freed VRAM before
llama.cpp asks for it.

## Testing

```sh
bash tests/run_tests.sh      # manifest + QML + helper suites
bash tests/preflight.sh      # the four marketplace gates, run locally
git config core.hooksPath .githooks   # run preflight on every push
```

The helper suite runs against a faithful `llama serve` test double, so it never
launches a real model.

### QML linting

`qmllint` on `PATH` is often Qt5 and cannot parse Quickshell's `qs.*` imports.
`tests/test_panel.sh` therefore prefers `/usr/lib/qt6/bin/qmllint` when it
exists and skips with a notice otherwise.

## Vendored security baseline

`tests/marketplace-baseline/` holds unmodified copies of the Omarchy plugin
marketplace's Automated Security Baseline scanner. Keep them unmodified so the
local result matches the marketplace's exactly.
