# Direct renderable examples

`direct_renderables.exe` is an executable example of the imperative
`opentui-core` API. It creates a retained `Box` containing `Text`, renders the
scene into a caller-owned output buffer, updates both renderable properties,
and closes the scene explicitly.

Run it from the repository root with:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/direct_renderables.exe
```

Its Cram transcript lives in
[`direct_renderables.t/run.t`](direct_renderables.t/run.t). Run the
black-box example check with:

```sh
nix develop -c dune runtest packages/opentui-core/examples
```

The example does not enter terminal mode, own an event loop, use Lwd, or
implement widget positioning. Its Box border is applied as a one-cell Yoga
inset, so the Text child demonstrates retained composition rather than drawing
border characters itself. General padding and positioning are outside this
example. Lwd, the OCaml incremental-computation library for reactive bindings,
is not used by this executable.
