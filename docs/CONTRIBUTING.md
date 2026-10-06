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
├── assets/llama.svg          Original icon
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
