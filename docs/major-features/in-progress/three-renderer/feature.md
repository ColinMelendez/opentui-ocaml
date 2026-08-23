# Three renderer

Status: planned; no implementation exists yet.

This feature defines the OCaml replacement for the reference `@opentui/three`
package: a retained 3D scene graph, a WebGPU-backed renderer, and the
cell-conversion boundary that presents rendered pixels as terminal cells. The
feature spans three new packages and composes with the existing `opentui-core`
renderer, framebuffer renderables, and post-processing stack.

## Purpose

The reference package renders a three.js scene through its WebGPU renderer
into an offscreen canvas mock, reads pixels back, and converts each 2x2 pixel
block into one terminal cell using a quadrant-glyph algorithm. three.js itself
is not portable; its role is. The OCaml port provides:

- an imperative scene-graph API whose shape and semantics mirror the subset of
  three.js that reference consumers exercise;
- a WebGPU rendering core built directly on `webgpu.h` through wgpu-native,
  replacing three.js's node-material pipeline with hand-written WGSL render
  pipelines for the supported material families;
- a verbatim-port compute pass for supersampling and cell conversion, so the
  observable cell output matches the reference algorithm rather than a
  re-derived approximation.

## Reference correspondence

Reference paths are relative to `vendor/opentui/packages`.

| Reference source | OCaml correspondence | Responsibility |
| --- | --- | --- |
| `three/src/WGPURenderer.ts` | `Opentui_three.Three_cli_renderer` | Options, active camera, cell-aspect ratio, resize wiring, `draw_scene`, super-sample toggle, stats overlay. |
| `three/src/ThreeRenderable.ts` | `Three.Renderable` composed over `Renderables.Frame_buffer` | Buffered, live retained renderable owning engine + scene + camera with auto-aspect resize. |
| `three/src/canvas.ts` | Internal readback module over `Opentui_wgpu` | Offscreen texture lifecycle, staging-buffer readback, 256-byte row alignment. |
| `three/src/shaders/supersampling.wgsl` | Pinned WGSL asset in `packages/opentui-three` | Quadrant-cell conversion compute pass; ported verbatim including alpha blending. |
| three.js surface used by reference demos | `Opentui_three.Three.*` modules | Vector2/3/4, Matrix4, Quaternion, Euler, Color, Object3D tree, Scene, Group, Mesh, cameras, geometries, materials, lights, textures. |
| `three/src/TextureUtils.ts` | `Three.Texture_utils` | Procedural checkerboard/gradient/noise textures; loading through `opentui-core.Image` decode instead of Jimp. |
| `three/src/SpriteResourceManager.ts`, `SpriteAnimator.ts`, `animation/*` effects | Phase 4 sprite modules | Texture-atlas sprites, frame animation, particle explosion effects. |
| `three/src/physics/physics-interface.ts` | `Three.Physics` module type | Seven-method 2D physics contract; adapters implement it against real engines. |
| `three/src/physics/PlanckPhysicsAdapter.ts`, `RapierPhysicsAdapter.ts` | `Box2d_adapter` over `opentui-box2d` | Box2D v3 backing; Planck.js is itself a Box2D port, so semantics transfer. |
| `bun-webgpu` (transitive reference dependency, backed by Dawn) | `packages/opentui-wgpu` (backed by wgpu-native) | Corresponding typed `webgpu.h` boundary: instance, adapter, device, buffers, textures, pipelines, mapAsync bridging. Backend internals differ; parity is defined at the WebGPU and rendered-cell contracts. |

## Package layering

```text
              OCaml application
                     │
                     ▼
               opentui-three     scene graph, WGSL render pipelines,
                │        │       cell conversion, Three_cli_renderer facade,
                │        │       sprites/effects, Physics adapters
        ┌───────┘        └────────┐
        ▼                         ▼
  opentui-core              opentui-wgpu   typed webgpu.h binding
  Renderer,                               over wgpu-native
  Frame_buffer/Owned_buffer,                   │
  Image decode, pre_render drivers,            ▼
  live leases, resize events          wgpu-native: hash-pinned official release,
                                      exposed by Nix and linked as a shared library

  opentui-box2d         vendored Box2D v3 source, built through CMake into a
       ▲                static library; independent of opentui-core and
       ┊ (phase 5)      opentui-wgpu, but from phase 5 a dependency of
                        opentui-three through the Physics adapters
```

`opentui-core` remains GPU-agnostic and takes no dependency on `opentui-wgpu`;
`opentui-three` depends on both independently. `opentui-box2d` depends on no
OCaml package; `opentui-three` acquires its dependency only in phase 5.
`opentui-wgpu` follows the `opentui-raw` ownership discipline: typed tokenized
handles, explicit close, borrowed-buffer rules, structured errors at every
boundary. It exposes WebGPU concepts without publishing raw pointers to higher
levels.

## Rendering contract

- One frame of `draw_scene ~root ~buffer ~delta_time` renders through the
  engine's single active camera (set via `set_active_camera`, mirroring the
  reference `drawScene(scene, buffer, dt)` signature). One frame performs:
  scene traversal and world-matrix update, draw-list collection with opaque
  front-to-back and transparent back-to-front sorting, per-material pipeline
  selection, uniform upload, render pass into the offscreen target, optional
  2x supersampling compute pass, staging-buffer readback, and cell writes
  through `Owned_buffer.set_cell_with_alpha_blending`.
- Framebuffers backing three content are created with alpha respected
  (`Frame_buffer.create ?respect_alpha:true`); transparent and
  semi-transparent scene output composites onto existing framebuffer content
  exactly when the reference `respectAlpha` renderables do.
- Cell conversion implements the reference quadrant algorithm: per cell the
  2x2 pixel block selects the two most color-distant samples, orders them by
  luminance, and emits one of sixteen Unicode quadrant glyphs with
  foreground/background assignment. Super-sample modes are `None`, `Cpu`, and
  `Gpu` with the same cycling behavior as the reference toggle.
- Camera projection defaults the aspect ratio to terminal width divided by
  twice the terminal height, honoring `CELL_ASPECT_RATIO`, mirroring the
  reference default. Focal-length construction derives field of view as the
  reference does.
- Output color space is linear working space with no tone mapping, converted
  once at cell emission, matching the reference renderer configuration.
- GPU work is confined to the renderer owner domain. `mapAsync` completion is
  bridged inside `opentui_wgpu`; higher layers observe synchronous,
  result-bearing operations.
- Frame execution mirrors the reference concurrency exclusion invariant: one
  readback buffer per path, `mapAsync` awaited before cells are written, and
  a concurrent `draw_scene` call rejected with a structured error. (The
  reference warns and returns; the OCaml contract deliberately reports
  instead.) Pipelined in-flight frames are an intentional divergence and are
  out of scope until measured frame timing requires them; if introduced later
  they need explicit ordering, cancellation, buffer-lifetime, and backpressure
  contracts.
- Staging representation is byte-exact. Pixel readback buffers, uniform
  buffers, and vertex staging use `Bigarray.Array1` of `char` (or
  `int8_unsigned`) so the same memory passes into C stubs without copies;
  explicit pack/unpack helpers place little-endian `f32`, `u32`, and RGBA8
  fields at documented offsets, honoring WGSL uniform alignment. Mapped
  readback ranges are the exception: `mapAsync` exposes wgpu-owned memory, so
  a mapped range is a scoped borrowed view that is decoded into cells - or
  copied into an OCaml-owned staging array - strictly before `unmap`, and it
  never escapes the mapping lifetime. Uniform and vertex Bigarrays owned by
  OCaml may pass directly to synchronous queue-write calls. `floatarray`
  never crosses a native or WGSL boundary; it remains available for pure
  arithmetic scratch such as intensity fields.
- Framebuffer clearing is explicit on both integration paths. `Three.Renderable`
  clears its owned framebuffer to the configured clear color immediately
  before every draw; callers using `Three_cli_renderer` directly retain
  responsibility for clearing their supplied buffer, matching the reference
  demos that clear transparent each frame before `drawScene`.

## Ownership and lifecycle

- Scene objects are OCaml-owned mutable records; native GPU resources
  (vertex/index buffers, textures) are created lazily and released explicitly.
  Destroying the owning `Three_cli_renderer` releases all cached GPU state.
- Geometry uploads are cached per geometry instance; mutating geometry
  attributes after first upload requires an explicit invalidation call, never
  silent re-upload.
- Textures wrap decoded `Image` values or owned RGBA byte buffers; the
  renderer borrows them only within a frame.
- The physics adapter owns its Box2D world; rigid bodies are invalidated when
  removed or when the adapter closes.

## Native artifacts

Native artifact policy differs by dependency according to its upstream
distribution:

- wgpu-native comes from an official, version-pinned release archive fetched
  by a Nix fixed-output derivation with a recorded SHA-256 hash. The derivation
  selects the archive by `stdenv.hostPlatform.system`, validates the expected
  `webgpu.h`, `wgpu.h`, metadata tag, and platform shared library, then exposes
  their immutable store paths through a generated `wgpu-native.pc`. Headers
  and library always come from the same archive. The initial artifact set pins
  wgpu-native `v29.0.1.1`; exact archive names and hashes live in `flake.nix` as
  the implementation source of truth. Supported targets are macOS aarch64 and
  Linux x86_64/aarch64; an absent upstream artifact is an explicit
  unsupported-target error rather than an implicit source build.
- `opentui-wgpu` uses `dune-configurator` and `pkg-config` to generate its C
  compile and link flags. Dune performs no download and does not search
  unpinned system locations. The Nix shell supplies wgpu-native as a
  `buildInput` and `pkg-config` as a `nativeBuildInput`.
- Development and CI link the wgpu-native shared library. Nix owns store-path
  runtime linking; a future non-Nix distribution must bundle the matching
  shared library and install a relative `$ORIGIN`/`@loader_path` rpath. A
  maintainer-only source derivation may be added for upstream diagnosis, but
  it is not a silent fallback or a supported product build path.
- Box2D v3 remains a vendored git submodule built by a dune rule through CMake
  into a static library with tests and examples disabled.

## Phases and acceptance criteria

Phase 0 - native foundation spike:

- The Nix wgpu-native derivation fetches, hash-verifies, and validates the
  pinned official archive for macOS aarch64 and Linux x86_64/aarch64. CI builds
  each system natively; future cross configurations continue selecting by the
  target `hostPlatform`, not the build machine.
- `opentui-wgpu` discovers only the derivation-provided `wgpu-native.pc` and
  links the shared library. A loader audit (`otool -L` on macOS, `readelf -d`
  on Linux) proves that a test executable resolves it from the Nix store
  without global `DYLD_LIBRARY_PATH` or `LD_LIBRARY_PATH` configuration.
- An `opentui-wgpu` headless test clears an offscreen texture, reads it back,
  and asserts the round trip without a window surface.
- mapAsync-to-Eio bridging is proven under repeated-frame load with no
  deadlock and no runtime-lock violations.
- The CI GPU strategy is settled: either software rendering (lavapipe) runs
  the suite, or GPU-dependent tests are host-gated with loud skips.

Phase 1 - spinning cube lite:

- Math modules pass known-value tests (matrix products, quaternion/Euler
  round trips, projection construction).
- A rotating lambert-shaded cube with directional plus ambient light renders
  into a Memory-output renderer; snapshot tests assert cell-level structure.
- `Three_cli_renderer` exposes create/init/draw_scene/set_active_camera/
  set_background_color/set_size/toggle_super_sampling/render_stats/destroy
  with reference option names.
- A runnable demo executable renders the cube interactively.

Phase 2 - supersampling and materials parity:

- The ported WGSL compute pass produces cells identical to a CPU oracle
  implementation of the same algorithm on shared fixtures.
- Phong materials, point lights, emissive terms, and textured materials with
  wrap/filter controls render correctly in snapshot tests.
- Stats overlay, super-sample toggling, and save-to-file behave as the
  reference.

Phase 3 - retained integration:

- `Three.Renderable` over `Frame_buffer` survives resize, respects
  auto-aspect, and drives frames through the pre_render driver.
- Remaining geometries (cylinder, cone, torus, torus knot, icosahedron),
  orthographic camera, wireframe rendering, and material side modes ship with
  tests. A reduced adaptation of the lights-phong demo ports, explicitly
  scoped to the supported surface: `Torus_knot_geometry` replaces
  `TeapotGeometry` (curved-surface normal coverage), standard
  `Mesh_phong_material` with map/specular/emissive replaces node-material TSL
  graphs, and scene fog is omitted. Any further gap between that demo and this
  contract is documented at port time rather than silently dropped.

Phase 4 - sprites and effects:

- Atlas sprites, frame animation, particle generation, and the exploding
  sprite effect match reference observable behavior on fixtures.

Phase 5 - physics adapters:

- `opentui-box2d` builds from vendored source in clean CI.
- `Box2d_adapter` satisfies contract tests derived from
  `physics-interface.ts`; the physics-driven exploding-sprite demo runs.

## Risks

This register is exposed for review and will be stripped item by item as each
risk is retired by implementation evidence.

Build and artifacts:

1. Release-asset stability: wgpu-native must continue publishing all three
   target archives with the expected headers, metadata, and shared-library
   layout. The fixed-output hashes prevent unnoticed replacement, while the
   derivation's layout checks make drift loud. Retire for the pinned release
   when all three derivations build in CI; reconsider the delivery policy
   explicitly when upgrading or adding a target.
2. Linux binary baseline: upstream Linux archives target manylinux_2_28, but
   their actual dynamic dependencies and behavior under Nix must be proven on
   both x86_64 and aarch64. Do not paper over failures with a global library
   path. Retire when loader audits and the headless round-trip test pass on
   both Linux targets.
3. Shared-library delivery: Nix store rpaths cover development and CI, not a
   future executable copied outside the store. Non-Nix packaging must place
   the matching library beside the artifact, use a relative platform rpath,
   and carry required license notices. Retire when that distribution format
   exists and is tested; it does not block the Nix-only Phase 0 spike.
4. CMake option drift for Box2D v3: the dune rule must pin static-library and
   no-test configuration explicitly. Retire when the rule encodes every flag.

Runtime and GPU environment:

5. No-GPU environments: adapter creation must return a structured error, not
   crash, and test gating must be deliberate. Proven so far: x86_64-linux
   through mesa lavapipe and macOS through Metal run the full headless suite
   in CI; aarch64-linux lavapipe rejects adapter creation outright with a
   native "Validation Error" whose cause is invisible until the binding gains
   wgpu log/error capture (see 16b). Interim contract: hosts without a usable
   device skip loudly with the structured diagnostic, while setting
   `OPENTUI_WGPU_REQUIRE_DEVICE=1` turns those skips into hard failures for
   local enforcement. Retire when aarch64-linux either runs the suite or is
   formally dropped from the supported target list, and when adapter failures
   surface their underlying native diagnostics.
6. mapAsync threading: completion callbacks fire on wgpu-owned threads; stubs
   must register those threads with the OCaml runtime before signaling, and
   polling must not deadlock the owner domain. Retired by design before the
   stress test became necessary: buffer-map callbacks are registered with
   `WGPUCallbackMode_WaitAnyOnly`, which forbids firing everywhere except
   inside our own `wgpuDevicePoll` calls on the calling thread, so no callback
   can ever enter OCaml from a foreign thread. The repeated-frame headless
   test passes 30 frames with no deadlock.
7. Readback serialization: per-frame mapAsync stalls CPU-GPU overlap. This is
   reference parity - the reference also awaits readback immediately, owns one
   readback buffer per path, and rejects concurrent draw calls - so no
   mitigation is planned until measured frame timing in the demo misses target
   FPS. Retire when the demo holds target FPS or a pipelining divergence is
   specified with ordering, cancellation, buffer-lifetime, and backpressure
   contracts.
8. Copy alignment: `copyTextureToBuffer` requires 256-byte row alignment; the
   readback path must handle padded strides. Retired: the headless round-trip
   renders at 61-pixel width (244-byte natural row) through the padded 256-byte
   stride and verifies exact pixel values.
9. Cross-backend float divergence: Metal and lavapipe may differ in low-order
   bits, breaking naive golden snapshots. Snapshot tests assert cell structure
   (glyph indices, coarse luminance buckets) rather than exact RGB. Retire
   when snapshot fixtures pass on both backends.
10. Y-flip confusion across seams: texture upload orientation, readback
    origin, and cell-grid origin each flip differently; the reference loader
    flips images vertically and sets `flipY = false`. One normalization note
    must be written before Phase 1 geometry work. Retire with a documented
    convention plus a textured-cube test proving orientation.
11. wgpu-native v29.0.1.1 known quirks (re-validate on every pin upgrade):
    first, buffer-map completion is not wired into the futures API - a map
    registered under either wait-any mode panics "not implemented" inside
    wgpu-native when completion is awaited - so the binding drives map
    callbacks through the `wgpuDevicePoll` extension instead, which keeps
    completion on the calling thread and is documented in the stub source.
    Second, descriptors whose `WGPUStringView` fields are `{NULL, 0}` are
    misparsed downstream (validation then observes garbage in the following
    field), so every descriptor carries a real label. Both quirks were
    reproduced against a pure C driver before the OCaml binding adopted its
    workarounds; both deserve upstream reports. Retire when a pin upgrade
    makes either workaround unnecessary.

API and semantics:

12. Color-space mistakes produce washed-out or dark output. Lock the linear
    working-space decision behind a mid-gray reference-value test. Retire in
    Phase 1 snapshots.
13. Scene-graph cycles (adding an ancestor as descendant) need explicit
    structured validation errors. Retire with a unit test.
14. Geometry cache invalidation after attribute mutation is contractual;
    silent staleness is forbidden. Retire with the invalidation API and test.
15. Save-to-file depends on emitting encoded PNG bytes out of `Image`; the
    extraction path needs verification against `ensure_encoded_png`. Retire in
    Phase 2 with the first saved screenshot test.
16. `CELL_ASPECT_RATIO` override parity is small but observable. Retire with
    an aspect-construction test.
16b. Uncaptured GPU errors have no structured path into OCaml yet: the device
     is created without an error callback, so void C-API calls
     (`begin_render_pass`, `copy_texture_to_buffer`, and from Phase 1 onward
     pipeline creation and buffer uploads) can fail silently while the frame
     returns [Ok]. The Phase 0 round-trip catches such failures through pixel
     assertions, which stops working once scenes are non-trivial. Before any
     pipeline work lands, `opentui-wgpu` must capture the uncaptured-error and
     device-lost callbacks into owner-local state and surface them as
     structured errors after submission. Blocking polls also hold the OCaml
     domain for the readback duration; acceptable at current resolutions,
     revisit if measured frame timing demands overlap.

Repository policy:

17. Repository constraints apply throughout: byte-exact staging for all
    GPU-facing data (see the staging contract above), `floatarray` reserved
    for arithmetic scratch such as intensity fields, no polymorphic comparison
    (matrix equality uses dedicated functions), loops over recursion in hot
    paths, structured results at every native boundary, warnings treated as
    errors, no ppx. Matrix inversion returns an option or result, never
    raises. Enforced by review per phase.
18. Box2D unit scale is meter-tuned while sprite-effect physics operates at
    pixel scale; tunneling and weak gravity result from naive scales. One
    pixel-to-meter constant must be agreed and documented in the adapter
    before Phase 5. Retire with the adapter design note.

## Non-goals

- Porting three.js internals: node materials, custom shader authoring,
  loaders beyond images, morph/skinning animation, raycasting until a consumer
  needs it.
- Windowed or swapchain presentation; rendering targets terminal cells only.
- 3D physics; Jolt remains future work behind the same adapter contract.
- Replacing or extending the audited OpenTUI Zig ABI; `opentui-wgpu` is a
  separate seam.
- Process-global GPU singletons; each renderer owns its device unless callers
  share devices explicitly.
