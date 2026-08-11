# Package graph

The monorepo is intentionally built from the bottom up:

```text
opentui-raw
├── opentui-native       native renderer, buffers, renderables, and layout bindings
│   └── opentui-core     retained OpenTUI scene model over the native layer
│       └── opentui-lwd  fine-grained reactive bindings (later)
│           └── opentui-widgets (later)
└── opentui-terminal     terminal modes, input framing, and decoding
    ├── opentui-terminal-eio      optional Eio/Cstruct runtime boundary
    └── opentui-terminal-eio-unix Unix signal, size, and tty scope
```

`opentui-terminal` is kept beside the native layer rather than below it because terminal input/output policy should remain usable without importing the renderer's object model. An application can compose the terminal, native, and core layers at its boundary.

The first terminal-side slice is now `opentui-terminal`'s reusable
`Byte_queue`, framing `Stdin_parser`, compositional `Key_decoder`, and
stateful `Mouse_decoder`, writer-free `Terminal_modes`, compositional
`Input_decoder`, and pure `Input_coordinator`. It owns
bounded `Bigarray.Array1` input storage, cursor compaction, split-safe protocol
framing, common semantic key naming/modifiers, SGR/X10 mouse semantics, and
owned event/paste payloads. The pure package leaves Eio flow ownership and
output lifecycle to the optional runtime package.

`opentui-terminal-eio` is the optional runtime package for Eio/Cstruct flow
reads, output, bounded-event wakeups, and caller-run dispatch. Its input flow
offers decoded events synchronously to a caller-owned sink and stops reading
when that sink applies backpressure; an `Event_queue` sink provides the
optional bounded lossless/coalescing handoff. Its revision wakeup and
race-safe dispatcher do not create fibers or take ownership of the switch. It
binds writer-free mode transitions to a caller-owned Eio sink without adding
Eio to the parser package.

`opentui-terminal-eio-unix` is a separate Unix-only runtime package. Its
caller-invoked probe validates `Terminal_size` values and maps OS errors;
`Resize_source` owns the scoped `SIGWINCH` notification, and
`Terminal_session` owns saved termios restoration plus ANSI reset while
leaving the descriptor and sink with the caller.

The host-gated `test_native_terminal_pty` smoke composes the optional Eio
boundary with native frames through a Unix PTY. It is an acceptance test for
mode restoration, raw tty restoration, input/resize handoff, native resize,
and output. The runtime test separately proves the signal-owner, wakeup, and
dispatch contracts.

The first `opentui-native` slice composes `opentui-raw` behind an imperative
renderer/frame lifecycle and an owner-scoped `Layout` tree. Its opaque frame
token owns the next-buffer editing window and is consumed by `present`; its
layout nodes own only copied Yoga dimensions/results. It does not expose native
handles, and its `Text_renderable` leaf only holds a layout-node reference and
maps its copied origin to a caller-owned frame. It does not introduce terminal,
retained-scene, measure-callback, Lwd, or widget policy.

`opentui-core` is now the first retained imperative layer above that native
composition. It owns a scene renderer and Yoga tree, gives each container or
text node a persistent identity, invalidates layout and rendering on mutation,
flushes one caller-owned output frame, and dispatches synthetic pointer events
to the deepest hit node before bubbling to its parents. It currently supports
fixed-size containers and text only; terminal-event adaptation, richer Yoga
styles, custom renderables, Lwd, and widgets remain outside this increment.

The graph is a design target, not a promise to create a package for every subsystem. The `Buffer` module currently in `opentui-raw` is only the ABI-level borrowed view needed to exercise the pinned renderer; it is not the retained scene or renderable model. Yoga/layout and native renderables should initially be modules of `opentui-native`; they become separate packages only if they have a stable independent consumer.
