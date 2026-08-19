# Backend choice

Non-normative context. This record explains why the three renderer builds on
wgpu-native and Box2D v3, and which alternatives were discarded. The active
contract is `../feature.md`; nothing here defines API or behavior.

## Decision summary

| Concern | Chosen | Discarded alternatives |
| --- | --- | --- |
| GPU device layer | wgpu-native (Rust implementation, C API) from official release binaries | Google Dawn; pure-OCaml software rasterizer; OpenGL/OSMesa FFI |
| 2D physics engine | Box2D v3 (vendored source) | Jolt (via joltc); Rapier (Rust); Havok WASM |
| Artifact delivery | Hash-pinned wgpu-native release archives through Nix; Box2D from pinned source | Building wgpu-native in Dune; unpinned system or npm binaries |

## GPU device layer

### wgpu-native (chosen)

- Upstream `@opentui/three` runs through `bun-webgpu` 0.1.7, which packages a
  Dawn FFI rather than wgpu-native. The OCaml port therefore does not claim
  backend-internal identity: parity lives at the common `webgpu.h` behavior,
  renderer configuration, cell-conversion algorithm, and observable cell
  output.
- Implements the stable `webgpu.h` C header designed for bindings into
  higher-level languages; the C surface is flat, handle-based, and matches the
  repository's existing C-stub discipline (`opentui-raw`).
- Publishes official release archives for every initial target, including
  Linux aarch64. Each archive contains the matching `webgpu.h`, wgpu-native
  extension header, metadata tag, static archive, and shared library, allowing
  the binding ABI and implementation to be pinned as one hash-verified unit.
- MIT/Apache-2.0 dual license.
- Powers Firefox and Deno WebGPU, so the implementation is exercised at scale.

Known caveat recorded in the risk register: wgpu-native historically lags the
upstream stable `webgpu.h` revision slightly. The binding pins the header that
ships with the pinned wgpu-native revision rather than assuming spec currency.

### Dawn (discarded)

- Dawn is the reference package's actual device backend and implements
  `webgpu.h`, but `bun-webgpu` distributes Dawn as an implementation detail of
  its Bun package rather than as a generic, versioned native SDK for this OCaml
  binding. Consuming those files would couple the Nix build to npm package
  layout and the reference wrapper's release choices.
- Building Dawn directly requires a substantially heavier C++ and GN/CMake
  toolchain, while wgpu-native publishes a smaller official target matrix that
  includes all three initial systems. Neither backend supplies the scene graph
  or cell renderer; those parity obligations remain in `opentui-three`.

### Pure-OCaml software rasterizer (discarded)

- Fully deterministic and dependency-free, and comfortably fast at terminal
  resolutions (~15-50k pixels per frame).
- Rejected because the project owner explicitly preferred standing on modern
  existing libraries, wanted GPU headroom for particle effects and sprites,
  and valued architectural symmetry with the reference WebGPU pipeline
  (including a verbatim port of the reference supersampling compute pass,
  which requires a compute-capable backend).

### OpenGL via OSMesa/EGL (discarded)

- Legacy API surface; software paths are slower than lavapipe-class Vulkan;
  no path to the reference compute-shader algorithm without GLSL translation;
  no upstream correspondence.

## 2D physics engine

The reference `physics-interface.ts` contract is seven methods: create rigid
body (translation, linear/angular damping), create cuboid collider
(restitution, friction, density), remove rigid body, apply impulse, apply
torque impulse, read translation, read rotation. Any mature 2D engine covers
it; the differentiators are binding friction and semantics provenance.

### Box2D v3 (chosen)

- Official plain-C API (`box2d.h`) designed for embedding and language
  bindings; small pure-C codebase that builds through CMake into a static
  library, matching the repository's vendored-build precedent.
- Planck.js, one of the two reference adapters, is itself a JavaScript port of
  Box2D, so simulation semantics transfer almost one-to-one to
  `Box2d_adapter`.
- Apache-2.0 license; single-maintainer continuity under Erin Catto with
  active v3 development.

### Jolt via joltc (deferred)

- 3D physics; heavier C++ build; would serve future 3D physics behind the same
  adapter module type but adds nothing to the 2D sprite-effect use cases that
  motivate this feature.

### Rapier (discarded)

- The other reference adapter's engine; Rust with no official stable C ABI for
  native embedding. Binding it would require maintaining an FFI shim crate -
  strictly more moving parts than Box2D's official C API for equivalent
  semantics.

### Havok WASM (discarded)

- Requires embedding a WASM runtime into the OCaml process to call a physics
  engine; unacceptable indirection and licensing posture for this repository.

## Artifact delivery

wgpu-native uses its official prebuilt releases by default:

- A Nix fixed-output derivation pins the release URL and SHA-256 for each
  supported target. It selects by `stdenv.hostPlatform.system`, so native CI
  and a future cross toolchain resolve the target artifact rather than the
  build machine's artifact.
- The initial implementation pins wgpu-native `v29.0.1.1`; `flake.nix` owns
  the exact asset names and hashes so an upgrade changes one auditable map.
- The derivation validates the headers, metadata tag, and platform library,
  then publishes a `wgpu-native.pc`. `dune-configurator` queries that package;
  Dune itself neither downloads artifacts nor searches unpinned host paths.
- Development and CI prefer the shared library. The Nix compiler wrapper owns
  store rpaths; future standalone bundles must ship the same library with a
  relative `$ORIGIN` or `@loader_path` rpath and the required notices.
- The Linux archives' manylinux_2_28 baseline and both platforms' loader
  behavior remain Phase 0 acceptance questions, not reasons to carry a Rust
  toolchain and vendored Cargo graph before evidence demands it.
- A maintainer-only source derivation may support upstream debugging, but it
  is never an automatic fallback. Missing release assets make a target
  unsupported until the artifact policy is reconsidered explicitly.

Box2D keeps the source-build policy because it is a small C library with an
official embedding API and an already appropriate CMake path. Artifact policy
is therefore dependency-specific rather than a repository-wide requirement
that all native code share one provenance mechanism.
