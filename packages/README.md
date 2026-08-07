# Package graph

The monorepo is intentionally built from the bottom up:

```text
opentui-raw
├── opentui-native       native renderer, buffers, renderables, and layout bindings
│   └── opentui-core     retained OpenTUI scene model over the native layer
│       └── opentui-lwd  fine-grained reactive bindings (later)
│           └── opentui-widgets (later)
└── opentui-terminal     terminal mode, input decoding, and output lifecycle
```

`opentui-terminal` is kept beside the native layer rather than below it because terminal input/output policy should remain usable without importing the renderer's object model. An application can compose the terminal, native, and core layers at its boundary.

The first terminal-side slice is now `opentui-terminal`'s reusable
`Byte_queue`, framing `Stdin_parser`, compositional `Key_decoder`, and
stateful `Mouse_decoder`, writer-free `Terminal_modes`, and compositional
`Input_decoder`. It owns
bounded `Bigarray.Array1` input storage, cursor compaction, split-safe protocol
framing, common semantic key naming/modifiers, SGR/X10 mouse semantics, and
owned event/paste payloads. Output lifecycle and Eio integration remain
separate follow-on modules.

The first `opentui-native` slice composes `opentui-raw` behind an imperative
renderer/frame lifecycle. Its opaque frame token owns the next-buffer editing
window and is consumed by `present`; it does not expose native handles or
introduce terminal, retained-scene, Yoga-renderable, Lwd, or widget policy.

The graph is a design target, not a promise to create a package for every subsystem. The `Buffer` module currently in `opentui-raw` is only the ABI-level borrowed view needed to exercise the pinned renderer; it is not the retained scene or renderable model. Yoga/layout and native renderables should initially be modules of `opentui-native`; they become separate packages only if they have a stable independent consumer.
