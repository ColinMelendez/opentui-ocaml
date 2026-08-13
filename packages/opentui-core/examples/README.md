# Core examples

The examples directory contains executable programs for the public
`opentui-core` modules. `renderer_buffers.ml` demonstrates renderer ownership,
the shared borrowed-buffer view, drawing, resolved-character output, and
resize.

Run it from the repository root with:

```sh
nix develop -c dune exec ./packages/opentui-core/examples/renderer_buffers.exe
```
