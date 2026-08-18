# Core examples

The examples directory contains executable programs for the public
`opentui-core` modules:

- `renderer_buffers.ml` demonstrates renderer ownership, the shared
  borrowed-buffer view, drawing, resolved-character output, and resize using
  the headless `Memory` renderer output target.
- `opentui_demo.ml` is a port of the reference
  `vendor/opentui/packages/examples/src/opentui-demo.ts`: a tabbed showcase of
  styled text, borders, box titles, animation, and interactive controls. It
  runs through the Eio harness in `lib/app.ml` and drives the native renderer
  with the feed-backed `Sink` output target so styled frames reach the
  terminal through the same serialized output owner as terminal-mode and query
  writes.

The shared example helpers live in `lib/`:

- `app.ml` — the Eio application harness: terminal session (raw mode,
  alternate screen, mouse and kitty modes), the bounded input queue and
  dispatch loop, the renderer scheduler, and the renderer `Sink` wired to
  `Output_flow.write_frame`.
- `tab_controller.ml` — a port of `src/lib/tab-controller.ts`: a `Tab_select`
  bar plus one visible `Box` group per tab, with per-frame update callbacks
  and show/hide lifecycle.
- `standalone_keys.ml` — a port of `src/lib/standalone-keys.ts`: backtick or
  double-quote toggles the diagnostic console, Ctrl+C exits. The reference's
  debug-overlay, hit-grid dump, renderer start/stop/auto, and native
  arena-introspection keys are intentionally not bound yet and are documented
  in the module.
- `util.ml` — hex and HSV color helpers used by the demo.

Run the demo from the repository root inside the Nix shell:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/opentui_demo.exe
```

The frame rate defaults to 60fps; set `OPENTUI_DEMO_FPS` to run at a
different cadence, for example:

```sh
OPENTUI_DEMO_FPS=120 nix develop -c dune exec ./packages/opentui-core/examples/opentui_demo.exe
```

Keys: Left/Right arrows switch tabs, `t`/`r`/`b`/`l` toggle the Interactive
tab's borders, backtick/`"` toggles the console, Ctrl+C exits.
