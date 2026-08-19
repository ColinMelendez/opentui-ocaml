# Backend choice

Non-normative context. This record explains why the three renderer builds on
wgpu-native and Box2D v3, and which alternatives were discarded. The active
contract is `../feature.md`; nothing here defines API or behavior.

## Decision summary

| Concern | Chosen | Discarded alternatives |
| --- | --- | --- |
| GPU device layer | wgpu-native (Rust, C API) built from source | Google Dawn; pure-OCaml software rasterizer; OpenGL/OSMesa FFI |
| 2D physics engine | Box2D v3 (vendored source) | Jolt (via joltc); Rapier (Rust); Havok WASM |
| Artifact delivery | Build from pinned source in dune rules | Hash-pinned prebuilt release downloads |

## GPU device layer

### wgpu-native (chosen)

- Same foundation as the reference implementation: upstream `@opentui/three`
  runs through `bun-webgpu`, which wraps wgpu-native. Choosing it preserves the
  possibility of semantic parity with the reference renderer's behavior.
- Implements the stable `webgpu.h` C header designed for bindings into
  higher-level languages; the C surface is flat, handle-based, and matches the
  repository's existing C-stub discipline (`opentui-raw`).
- Ships a Cargo workspace with lockfile, so building from pinned sources is
  reproducible given a pinned Rust toolchain.
- MIT/Apache-2.0 dual license.
- Powers Firefox and Deno WebGPU, so the implementation is exercised at scale.

Known caveat recorded in the risk register: wgpu-native historically lags the
upstream stable `webgpu.h` revision slightly. The binding pins the header that
ships with the pinned wgpu-native revision rather than assuming spec currency.

### Dawn (discarded)

- Chromium-grade and implements the stable `webgpu.h` fully, but has no
  official prebuilt embedding artifacts and its build system (gn/ninja or
  large CMake configuration) is disproportionate for this repository's
  build-from-source dune-rule pattern.
- C++ toolchain weight in the Nix shell for no benefit over wgpu-native here,
  since neither choice provides a scene graph - the value is only the device.

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

Hash-pinned prebuilt wgpu-native release downloads were considered first and
discarded when the decision moved to building everything from source:

- Prebuilt Linux binaries couple to specific glibc versions; static archives
  ease linking but complicate licensing aggregation; dynamic libraries add
  rpath concerns on macOS.
- Source builds match the existing audited-Zig pattern: pinned revision in a
  submodule, deterministic rule, stamp-target caching of the expensive build.
- Cost accepted: Rust toolchain joins the Nix shell and cargo hermeticity
  needs resolving (see risk register items 1-2 in `feature.md`).
