# Architecture

This document defines the package boundaries and terminology of the OCaml
OpenTUI library. OpenTUI is a terminal user-interface framework with a
TypeScript reference implementation and a Zig renderer. The reference source
is checked out at `vendor/opentui`; the source correspondence is indexed in
the [source correspondence map](upstream-map.md). The contributor workflow
for translating a reference feature into OCaml is in
[`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Terms

| Term | Meaning in this repository |
| --- | --- |
| Reference source | The OpenTUI source in `vendor/opentui`. It defines the behavior and source paths that the OCaml implementation follows. |
| ABI | The C-compatible function and data representation used to call the Zig renderer. |
| Retained UI tree | A tree whose nodes remain allocated and keep their identities while properties change between frames. |
| Scene | The `opentui-core.Scene` owner of one retained UI tree, one renderer, and one Yoga layout tree. |
| Renderable | A retained node that contributes visual output, such as `Scene.Box` or `Scene.Text`. |
| Yoga | The layout engine used by `opentui-core` to calculate node positions and dimensions. |
| Eio | The OCaml library used for structured concurrency, terminal I/O, clocks, cancellation, and resource cleanup. |
| Lwd | The OCaml incremental-computation library intended for a reactive binding layer. It is not a dependency of the public packages. |

## Packages and dependency direction

The repository contains two public OCaml packages:

| Package | Responsibility | Dependency direction |
| --- | --- | --- |
| `opentui-raw` | Calls the reference Zig renderer through C, validates ABI values, and owns foreign resource lifetimes. | Independent of `opentui-core`. |
| `opentui-core` | Provides the retained UI tree, renderer composition, renderables, terminal protocols, and Eio/Unix terminal modules. | Depends on `opentui-raw`. |

The dependency direction is:

```text
OCaml application
       │
       ▼
opentui-core
       │
       ▼
opentui-raw
       │
       ▼
reference Zig renderer in vendor/opentui
```

`opentui-raw` is a separate package because ABI calls and foreign-resource
lifetimes have different invariants from retained UI ownership and terminal
policy. The higher-level package can use checked renderer operations without
publishing packed handles, raw pointers, or C callback details.

## Package-local validation and tooling

Code that exercises one package is stored in that package directory:

| Package directory | Contents |
| --- | --- |
| `packages/opentui-core/test` | Tests for scenes, renderables, the renderer, terminal protocols, and Eio/Unix integrations. |
| `packages/opentui-core/examples` | Executable examples of the public core API and their Cram transcripts. |
| `packages/opentui-core/reference` | Optional comparisons between core behavior and the TypeScript reference source. |
| `packages/opentui-core/bench` | Release-profile workloads, allocation baselines, and tracing wrappers for core behavior. |
| `packages/opentui-raw/test` | Tests for the raw ABI, C stubs, foreign ownership, and the native link seam. |

The repository-level `docs/` directory is intentionally different. Its active
documents describe the relationship between both OCaml packages, the checked
out reference source, and repository-wide implementation decisions. They are
not features owned by one package. Historical notes remain under
`docs/archive/` and are not part of the active package contract.

The repository does not contain a widget package or an Lwd integration
package. The source map lists the React and Solid reference packages and the
control and composition paths that are deferred.

## `opentui-core/src`

The `opentui-core/src` tree follows `vendor/opentui/packages/core/src`. A
directory or module with a different OCaml name is listed in the source map.

```text
src/
├── renderer.ml              frame lifecycle and output
├── yoga.ml                  layout ownership and readback
├── renderables/             retained visual nodes
│   ├── box.ml
│   └── text.ml
├── lib/                     terminal protocol and input support
│   ├── stdin_parser.ml
│   ├── byte_queue.ml
│   ├── input_coordinator.ml
│   ├── input_decoder.ml
│   ├── event_queue.ml
│   ├── key_decoder.ml
│   ├── mouse_decoder.ml
│   ├── terminal_modes.ml
│   └── ...
├── platform/                Eio and operating-system integration
│   ├── eio_runtime/         Eio flows, output, wakeups, and dispatch
│   └── eio_unix_runtime/    termios, SIGWINCH, and terminal-size support
├── scene.ml                 retained UI-tree owner
└── native/                  OCaml errors for native composition
```

The names `eio_runtime` and `eio_unix_runtime` avoid a Dune namespace conflict:
with qualified subdirectories, a directory named `eio` or `unix` would shadow
the external OCaml modules `Eio` or `Unix`. Both directories remain under
`src/platform`. The source map records the reference `platform/*` directory
and explains this OCaml-specific split; `eio_runtime` and `eio_unix_runtime`
are not directories in the reference source.

## Effect boundary

The application-facing runtime is Eio-native. One Eio switch can own terminal
setup, input, output, clocks, cancellation, and cleanup. `opentui-core` keeps
the rendering and parsing operations synchronous: `Scene`, `Renderer`, Yoga,
renderable setters, the byte parser, and the bounded event queue do not start
fibers or perform terminal I/O.

An application fiber calls the synchronous renderer and parser operations. The
controlled API exposes `Scene.flush` as an explicit presentation boundary, so
an application may decide when to present a frame. That operation
is not the semantic replacement for reference `requestRender()`: a scheduler
added above this boundary must keep dirty-state invalidation, coalesced frame
requests, timing, and presentation distinct. This boundary keeps scheduling
and terminal resource lifetime out of per-cell rendering operations while
allowing Eio to own the surrounding application runtime.

## Translating TypeScript concepts

The OCaml API follows OpenTUI behavior and source organization without copying
TypeScript class syntax or JavaScript runtime mechanisms.

| Reference mechanism | OCaml representation |
| --- | --- |
| Base class and inheritance | An owned retained `Scene.Node` owns identity, tree ownership, and lifecycle. Concrete renderable modules own typed state and use the shared `Node.kind` dispatch shape. |
| Constructor option bag | Labelled arguments and typed records for reusable groups of values. |
| Public mutable property | A typed accessor and setter that preserve reference validation, clamping, equality/no-op, invalidation, and error behavior. |
| `EventEmitter` | Owner-local typed event channels composed into the scene, renderer, render context, or component. Synchronous registration-order dispatch, snapshot semantics, reentrancy, duplicate subscriptions, one-shot removal, callback exceptions, cleanup, and producer-owned scheduling remain explicit. Keyboard priority, pointer propagation, queueing, and backpressure remain separate dispatch systems. |
| Reference input handoff | `Input_coordinator` and `Event_queue` are explicit OCaml adapters. Backpressure and coalescing require tests for order, replacement position, multiplicity, ownership, and handoff behavior. |
| `RenderContext` / renderer reference | Explicit render-context capabilities retained by nodes; Eio capabilities remain at runtime/platform boundaries. |
| `requestRender()` | Dirty-state invalidation plus a coalesced future-frame request, distinct from an explicit `Scene.flush`/presentation operation. |
| React/Solid reconciliation | An Lwd binding, if added, attaches to the retained nodes rather than creating a second required tree. |

Each non-literal translation must have a corresponding source-map path and
architecture or feature documentation. The documentation must state the
ownership invariant and observable test behavior. The source map remains
path-oriented; detailed adapter and decomposition rationale belongs in the
longer documentation.

## Contribution workflow

The detailed translation rules, semantic decision checklist, and feature-porting
playbook are in [`CONTRIBUTING.md`](../CONTRIBUTING.md). The short workflow
below identifies the repository records that every implementation must update.

For a new feature:

1. Locate the analogous path under `vendor/opentui/packages`.
2. Place a core implementation under the corresponding `opentui-core/src`
   directory, unless the feature is an ABI adapter owned by `opentui-raw`.
3. Add or update its row in the [source correspondence map](upstream-map.md).
4. Add a behavior test under the owning package's `test/` directory and,
   where the behavior is comparable, a reference comparison under the core
   package's `reference/` directory.
5. Record any change in ownership, effects, events, or class-to-module
   translation.

The map marks features that have no implementation or that do not belong to a
terminal-only OCaml library. Those entries do not require placeholder modules.
