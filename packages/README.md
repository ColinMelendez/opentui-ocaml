# Packages

The product-facing OCaml package is [`opentui-core`](opentui-core/). Its
source tree mirrors the pinned OpenTUI core tree:

```text
opentui-core/src/
├── renderables/
├── lib/
└── platform/
    ├── eio_runtime/
    └── eio_unix_runtime/
```

[`opentui-raw`](opentui-raw/) is the deliberately separate native ABI seam.
It contains OCaml-specific ownership and C/Zig bindings rather than a second
user-facing renderable layer.

For an upstream-to-OCaml feature lookup, use
[`docs/upstream-map.md`](../docs/upstream-map.md). For package and effect
boundaries, use [`docs/architecture.md`](../docs/architecture.md).
