# opentui-raw

This package is the narrow waist between OCaml and the native OpenTUI ABI. It owns opaque native handles and, as the binding work progresses, the typed declarations and lifetime rules for native calls.

It deliberately does not contain a renderer tree, terminal event loop, reactive graph, or widget API. Those layers must be able to depend on a small and auditable boundary.
