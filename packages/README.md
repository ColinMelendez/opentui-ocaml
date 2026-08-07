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

The graph is a design target, not a promise to create a package for every subsystem. The `Buffer` module currently in `opentui-raw` is only the ABI-level borrowed view needed to exercise the pinned renderer; it is not the retained scene or renderable model. Yoga/layout and native renderables should initially be modules of `opentui-native`; they become separate packages only if they have a stable independent consumer.
