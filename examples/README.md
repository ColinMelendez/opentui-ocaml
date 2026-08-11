# Direct renderable examples

`direct_renderables.exe` is the first executable example for the
OpenTUI-shaped imperative track. It creates a retained `Box` and `Text`,
flushes them through one caller-owned output buffer, updates both renderable
properties, and closes the scene explicitly.

Run it from the repository root with:

```sh
nix develop -c dune exec ./examples/direct_renderables.exe
```

Its Cram transcript lives in
[`direct_renderables.t/run.t`](direct_renderables.t/run.t). Run the
black-box example check with:

```sh
nix develop -c dune runtest examples
```

The example intentionally stays below the terminal and reactive layers. It
does not enter terminal mode, own an event loop, use Lwd, or implement widget
positioning. The Box border is applied as a one-cell Yoga inset, so the Text
child demonstrates actual retained composition rather than drawing border
characters itself. More general padding and positioning remain future
direct-track work.
