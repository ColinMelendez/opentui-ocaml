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
- `opentui_markdown_demo.ml` is a port of the reference
  `vendor/opentui/packages/examples/src/markdown-demo.ts`: a scrollable
  `MarkdownRenderable` showcase with rich inline formatting, tables, lists,
  blockquotes, and fenced code, theme cycling, conceal toggling, and a
  streaming simulation. Fenced code renders as plain fallback text because
  the OCaml port does not yet ship a tree-sitter runtime.
- `opentui_scrollbox_mouse_test.ml` is a port of the reference
  `vendor/opentui/packages/examples/src/scrollbox-mouse-test.ts`: a focused
  `Scroll_box` hit-testing check with 50 hoverable item rows, mostly to
  exercise scrolling and scrolled-content hit-testing during the ongoing
  scroll-behavior work.
- `opacity_example.ml` is a port of the reference
  `vendor/opentui/packages/examples/src/opacity-example.ts`: overlapping boxes
  with individually toggleable opacity, nested opacity multiplication, and a
  live animation driven by the renderer's pre-render hook.
- `grayscale_buffer_demo.ml` is a port of the reference
  `vendor/opentui/packages/examples/src/grayscale-buffer-demo.ts`: animated
  grayscale patterns rendered once at terminal-cell resolution and once with
  native 2x supersampling.
- `timeline_example.ml` is a port of the reference
  `vendor/opentui/packages/examples/src/timeline-example.ts`: nested timelines,
  numeric property bindings, easing, looping, alternation, and progress bars.
- `slider_demo.ml` is a port of the reference
  `vendor/opentui/packages/examples/src/slider-demo.ts`: horizontal and vertical
  sliders with different ranges, viewport sizes, dimensions, mouse dragging,
  focus controls, and animated values.

The shared example helpers live in `lib/`:

- `app.ml` — the Eio application harness: terminal session (raw mode,
  alternate screen, mouse and kitty modes), the bounded input queue and
  dispatch loop, the renderer scheduler, and the renderer `Sink` wired to
  `Output_flow.write_frame`. The harness is on-demand by default; demos that
  correspond to reference `renderer.start()` calls acquire live rendering
  themselves.
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

Continuous rendering defaults to 30fps and requested frames are capped at
60fps. Set `OPENTUI_DEMO_FPS` to change the continuous target cadence, for
example:

```sh
OPENTUI_DEMO_FPS=120 nix develop -c dune exec ./packages/opentui-core/examples/opentui_demo.exe
```

Keys: Left/Right arrows switch tabs, `t`/`r`/`b`/`l` toggle the Interactive
tab's borders, backtick/`"` toggles the console, Ctrl+C exits.

Run the markdown demo:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/opentui_markdown_demo.exe
```

Markdown keys: `T` cycles themes, `C` toggles concealment, `S` starts or
restarts streaming, `E` toggles endless streaming, `X` stops streaming,
`[`/`]` adjust streaming speed, `?` toggles the help overlay, `ESC` closes the
overlay or exits, and Ctrl+C exits. Drag across Markdown text to select it and
copy the selection through OSC52 when the terminal supports it.

Run the scrollbox hit-test:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/opentui_scrollbox_mouse_test.exe
```

Scroll with the mouse wheel or arrow keys, hover rows to see the header
status update, click a row to append a message to the diagnostic console, and
use backtick/`"` to show it. Ctrl+C exits.

Run the opacity demo:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/opacity_example.exe
```

Opacity keys: `1`-`4` toggle each overlapping box between full and 30%
opacity, `A` starts or stops the animation, backtick/`"` toggles the console,
and Ctrl+C exits. The nested panel shows parent, child, and effective opacity.

Run the grayscale buffer demo:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/grayscale_buffer_demo.exe
```

Grayscale keys: Space pauses or resumes animation, `P` cycles the pattern,
backtick/`"` toggles the console, and Ctrl+C exits.

Run the timeline example:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/timeline_example.exe
```

Timeline keys: `P` pauses the main timeline, `R` restarts it, backtick/`"`
toggles the console, and Ctrl+C exits.

Run the slider demo:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/slider_demo.exe
```

Slider keys: `R` resets all values, `1`–`7` focuses a slider, backtick/`"`
toggles the console, and Ctrl+C exits. After focusing a slider, its orientation-
appropriate arrow keys adjust the value; Page Up/Down and Home/End also work.
Mouse click-drag changes slider values.
