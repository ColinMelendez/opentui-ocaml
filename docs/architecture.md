# Architecture

Status: current implementation contract, 2026-08-11.

This project is an OCaml implementation of the OpenTUI architecture on top of
the pinned native source in `vendor/opentui`. The vendor tree is the behavior
reference. The OCaml tree follows its public source paths wherever a feature
has an implementation; language-specific replacements are recorded in the
[upstream correspondence map](upstream-map.md).

## Packages

There are two product-facing layers today:

| Package | Purpose | Upstream relationship |
| --- | --- | --- |
| `opentui-core` | The main Eio-native OpenTUI-shaped API: renderer, retained nodes, renderables, terminal parsing, and terminal platform code. | Mirrors `vendor/opentui/packages/core/src`. |
| `opentui-raw` | The audited OCaml-to-Zig/C ABI and ownership seam. | Adapts `vendor/opentui/packages/core/src/zig`, `buffer.ts`, and `NativeSpanFeed.ts`; it has no direct TypeScript package equivalent. |

`opentui-lwd` is a future integration package corresponding to the role of
the upstream React and Solid packages. It is not part of the current public
surface. Widgets and application policy are not separate packages until the
mirrored core surface demonstrates that they need independent ownership or
dependencies.

## The `opentui-core/src` tree

```text
src/
├── renderer.ml              renderer and frame lifecycle
├── yoga.ml                  Yoga ownership and layout readback
├── renderables/             direct OpenTUI renderable implementations
│   ├── box.ml
│   └── text.ml
├── lib/                     pure protocol and terminal support
│   ├── stdin_parser.ml
│   ├── key_decoder.ml
│   ├── mouse_decoder.ml
│   ├── terminal_modes.ml
│   └── ...
├── platform/                Eio runtime and OS integration
│   ├── eio_runtime/         Eio flow, output, wakeup, and dispatch modules
│   └── eio_unix_runtime/    termios, SIGWINCH, and terminal-size modules
├── scene.ml                 retained owner used by the current vertical slice
└── native/                  OCaml-side errors for the raw renderer seam
```

The inner platform directory names are intentionally `eio_runtime` and
`eio_unix_runtime`: with Dune's qualified subdirectories, directories named
`eio` or `unix` would shadow the external OCaml modules of the same names.
They remain under the upstream `src/platform` location and are listed
explicitly in the correspondence map.

## Effect boundary

The application/runtime layer is Eio-native. `opentui-core` therefore depends
on Eio and Eio's Unix support, and callers use one Eio switch for terminal
resources, input, output, and cleanup.

The render hot path remains synchronous. `Scene`, `Renderer`, Yoga, renderable
setters, the byte parser, and the bounded event queue do not perform effects or
start fibers. An Eio fiber owns calls into the native renderer; this keeps
allocation and scheduling out of per-cell operations while making terminal
lifetime observable to Eio tracing.

The current Eio modules are explicit building blocks. An integrated
OpenTUI-shaped CLI renderer/runtime will be added only after this structural
baseline is reviewed. It will compose these modules rather than introduce a
second parser, scene, or renderer.

## OCaml translations of TypeScript concepts

The goal is recognizable behavior and source correspondence, not a class or
syntax-compatible TypeScript port.

| OpenTUI mechanism | OCaml replacement |
| --- | --- |
| Base class and inheritance | Abstract owned values composed around a retained node. |
| Constructor option bags | Labelled arguments and typed records where a group is reused. |
| Public mutable properties | Typed setters with validation and equality cutoffs. |
| `EventEmitter` | Typed callbacks with explicit cleanup at the owning boundary. |
| Ambient renderer/context | Explicit scene, parent, renderer, and Eio capabilities. |
| `requestRender()` | A caller-owned flush boundary; Eio schedules the boundary. |
| React/Solid reconciliation | Future Lwd bindings over the same retained nodes. |

These replacements must be recorded next to the corresponding upstream path.
No replacement is added merely to imitate a JavaScript implementation detail.

## Contribution rule

For every new feature:

1. Start at the corresponding path under `vendor/opentui/packages`.
2. Put the OCaml implementation under the matching `opentui-core/src`
   directory when it is a core feature.
3. Add or update one row in `docs/upstream-map.md`.
4. Add a behavior test and, where meaningful, a comparison against the pinned
   reference.
5. Record any class, event, ownership, or effect translation in the map.

If a feature is deferred or outside this project's scope, the map must say so
explicitly. Empty placeholder modules are not used to create a misleading
appearance of parity.
