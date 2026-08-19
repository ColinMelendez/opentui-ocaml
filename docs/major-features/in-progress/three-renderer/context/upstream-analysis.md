# Upstream @opentui/three analysis

Non-normative context. This record captures what the reference package actually
is, component by component, and the integration patterns its consumers rely on.
The active contract is `../feature.md`.

## Component map

Package root: `vendor/opentui/packages/three` (version 0.5.3 at analysis time).
Dependencies that matter: `three` 0.177.0 (scene graph + WebGPU renderer),
`bun-webgpu` 0.1.7 (native WebGPU device via wgpu-native), `jimp`
(image encoding for screenshots), and optional `rapier2d-simd-compat` /
`planck` physics engines.

| File | Lines | Role |
| --- | --- | --- |
| `src/WGPURenderer.ts` | ~292 | `ThreeCliRenderer` facade: options (`width`, `height`, `focalLength?`, `backgroundColor?`, `superSample?`, `alpha?`, `autoResize?`, `libPath?`), default perspective camera derived from focal length, cell aspect ratio handling, resize/debug/destroy event wiring, `drawScene(scene, buffer, dt)`, `toggleSuperSampling()`, `renderStats(buffer)`, `saveToFile`. |
| `src/canvas.ts` | ~462 | `CLICanvas`: WebGPU canvas mock. Owns readback staging buffer (256-byte aligned rows), GPU compute supersampling pipeline, CPU supersampling path, `saveToFile` screenshot path, texture double-buffering via `switchTextures()`. |
| `src/shaders/supersampling.wgsl` | ~200 | The cell-conversion algorithm (see below). Output is one 48-byte record per terminal cell: bg vec4, fg vec4, char u32, padding. |
| `src/ThreeRenderable.ts` | ~200 | Retained renderable wrapping engine + scene + camera; `buffered: true`, `live: true` defaults; auto-aspect resize; frame-callback driven draw into its own framebuffer. |
| `src/TextureUtils.ts` | ~196 | `loadTextureFromFile` (Jimp decode + vertical flip + nearest filtering + clamp wrap), procedural checkerboard / gradient (horizontal, vertical, radial) / octave-noise textures. |
| `src/SpriteUtils.ts`, `SpriteResourceManager.ts` | ~356 | Sprite-sheet atlas management over `THREE.Sprite`. |
| `src/animation/SpriteAnimator.ts` | ~633 | Frame-based texture-atlas animation playback. |
| `src/animation/SpriteParticleGenerator.ts` | ~435 | Grid-samples a sprite into particles with velocity/gravity/fade behavior. |
| `src/animation/ExplodingSpriteEffect.ts` | ~513 | Explosion effect built on the particle generator. |
| `src/animation/PhysicsExplodingSpriteEffect.ts` | ~429 | Same, driven through the physics adapter for gravity/collisions. |
| `src/physics/*` | ~171 total | Tiny adapter interface plus Rapier and Planck implementations (see interface below). |

The package's own code is roughly 3,500 lines; everything else it can do comes
from three.js (~1M+ lines). The portable surface is therefore the facade, the
canvas/readback layer, the WGSL algorithm, the scene-graph subset consumers
exercise, and the adapters.

## The quadrant-cell algorithm (supersampling.wgsl)

Per terminal cell, load the 2x2 pixel block (TL, TR, BL, BR) from the rendered
texture:

1. Compute pairwise squared RGB distance among the four samples; take the most
   distant pair as candidate colors.
2. Order candidates by luminance (0.2126 R + 0.7152 G + 0.0722 B) into dark
   and light.
3. Each of the four quadrants emits a bit (TL=8, TR=4, BL=2, BR=1) set when
   the sample is closer to the dark color.
4. The 4-bit pattern selects one of sixteen glyphs: space, ▗ ▖ ▄ ▝ ▐ ▞ ▟ ▘ ▚
   ▌ ▙ ▀ ▜ ▛ █.
5. All-dark cells use full block with foreground set to
   `averageColorsWithAlpha(pixels)` and background to the light candidate;
   all-light uses space with dark-candidate foreground and alpha-blended
   average background; mixed patterns use the dark/light candidates directly
   as fg/bg.

Note that `averageColorsWithAlpha` applies in the all-dark and all-light
branches under *both* algorithm variants; `sampleAlgo` only changes how the
four input samples are produced (raw 2x2 samples for variant 0 versus
straight-alpha horizontal blends per row for the pre-squeezed variant 1).

The comment "same as Zig implementation" in the shader indicates the native
buffer library contains an equivalent routine
(`bufferDrawSuperSampleBuffer`), which the OCaml audited ABI deliberately does
not yet expose - so the OCaml port owns this algorithm outright.

Without supersampling (mode `None`), each rendered pixel maps to one cell via
a full block glyph colored with the pixel value - one pixel per column, one
per row. With supersampling, render dimensions are 2x output dimensions in
both axes, making each cell cover exactly a 2x2 pixel block.

## Aspect ratio semantics

Default camera aspect is terminal width divided by twice terminal height,
reflecting character cells being roughly twice as tall as wide; the
`CELL_ASPECT_RATIO` environment variable overrides it. Focal-length
construction derives FOV as `2 * atan(height / (2 * focalLength))` in degrees;
the reference default camera sits at `(0, 0, 3)` looking at the origin with
near 0.1 and far 1000.

## Renderer configuration

The reference sets `NoToneMapping` and `LinearSRGBColorSpace` on the WebGPU
renderer and clears with the configured background color (alpha honored only
when `alpha: true`). Consumers typically create a `FrameBufferRenderable`,
clear it transparent each frame, call `engine.drawScene(root, framebuffer,
deltaTime)`, and stack post-processing filters on top through the renderer's
post-process registration.

## Consumer integration patterns (from reference demos)

`shader-cube-demo.ts` exercises nearly the whole surface:

- `new ThreeCliRenderer(renderer, { width, height, focalLength: 8,
  backgroundColor, alpha })` then `await engine.init()`.
- Scene assembly: `Scene`, `DirectionalLight` (+ its `target` object added to
  the scene separately), `PointLight(color, intensity, distance)`,
  `AmbientLight`, `Mesh(BoxGeometry, MeshPhongMaterial)` with `map`,
  `specularMap`, `normalMap`, `emissiveMap`, `shininess`, `specular`,
  `emissive`, `emissiveIntensity`.
- Per-frame mutation: `cubeObject.rotation.x += ...`, point-light orbit via
  `position.set(sin, y, cos)`, material swapping by reassignment.
- Camera control: `translateX/Y/Z`, `rotateY`, `lookAt`, aspect update +
  `updateProjectionMatrix()` on resize, `engine.setActiveCamera(cameraNode)`.
- Lookup by name: `sceneRoot.getObjectByName("cube")`.
- Visibility toggles on lights and visualizer meshes.
- Teardown: `engine.destroy()`, key/resize listener removal, post-process
  clearing.

This demo shape is the primary semantic target for API parity review; the
phase-1 acceptance demo is a deliberate reduction of it.

## Physics adapter interface

```ts
interface PhysicsWorld {
  createRigidBody(desc: { translation; linearDamping; angularDamping }): PhysicsRigidBody
  createCollider(desc: { width; height; restitution; friction; density }, body): void
  removeRigidBody(body): void
}
interface PhysicsRigidBody {
  applyImpulse(force): void
  applyTorqueImpulse(torque): void
  getTranslation(): { x; y }
  getRotation(): number
}
```

Planck adapter maps cuboid half-extents, restitution, friction, density
directly onto Box2D-family concepts; the Rapier adapter mirrors it. This
confirms Box2D v3 as a semantics-compatible backing engine.

## Facts relevant to the OCaml port

- Readback requires 256-byte row alignment in `copyTextureToBuffer`; the
  reference computes aligned stride per width and strips padding afterward.
- The reference flips loaded images vertically and sets `flipY = false`
  because its sampler convention differs from WebGL defaults - orientation
  conventions must be pinned explicitly in the OCaml renderer.
- Frame execution is not pipelined: `readPixelsIntoBuffer` awaits `mapAsync`
  immediately, each path owns exactly one readback buffer, and
  `ThreeCliRenderer` explicitly rejects concurrent `drawScene` calls.
  `CLICanvas.switchTextures()` alternates canvas textures between frames but
  does not establish in-flight readback overlap.
- Stats overlay reports render ms, readback ms (mapAsync + super-sample draw
  split), total draw ms, current mode, and algorithm; drawn as text cells at a
  fixed offset over the framebuffer.
