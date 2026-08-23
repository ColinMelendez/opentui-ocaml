# Phase 1 working state

Non-normative progress notes for the three-renderer record. This file
exists so any contributor (or fresh session) can resume Phase 1 without
re-deriving decisions or re-learning ABI facts. Strip or shrink it as
phases land and this knowledge moves into real code.

## Locked decisions (owner, verbatim where it matters)

- GPU device layer: wgpu-native v29.0.1.1, official release archives,
  Nix fixed-output derivations, pkg-config + dune-configurator, shared
  library linking. No prebuilt artifacts outside that pin; no implicit
  source-build fallback.
- Physics (phase 5): Box2D v3 vendored submodule + CMake.
- Scene-graph API: mutable records mirroring three.js imperative style
  (`mesh.rotation.x <- mesh.rotation.x +. speed`), not builders.
- Package/module naming: `opentui-three`, namespace
  `Opentui_three.Three.*` (private modules re-exported through
  `three.mli`).
- Acceptance demo phase 3: reduced lights-phong adaptation with
  `Torus_knot_geometry` standing in for `TeapotGeometry`.
- Phase 1 acceptance demo: spinning lambert cube ("spinning cube
  lite").

## Where things stand

Landed on main (all CI green, three targets):

- `9f3be0a` nix wgpu-native pin; `33e2792` package registration;
  `b285ed6` opentui-wgpu headless binding + readback tests;
  `156fd42`/`c3a87a9` CI Vulkan env; `45c2036` vendor repin +
  capability_probe_exports.patch; `a5ae278` bounded map waits;
  `14c1511`/`9351ef6` core test deadline fixes; `4d0a8c9`
  **Phase 1 slice A: math core** (Vector3/Matrix4/Quaternion/Euler/Color,
  seven known-value tests green).

Remaining Phase 1 slices:

- B: opentui-wgpu pipeline stubs (see ABI facts below) plus diagnostics
  capture (risk 16b: uncaptured-error callback in WGPUDeviceDescriptor,
  wgpu.h log callback).
- C: scene graph (Object3D dirty-flag world matrices), BoxGeometry with
  per-face normals, MeshBasic/Lambert materials, directional+ambient
  lights, PerspectiveCamera (focal-length FOV; aspect =
  terminal_width / (terminal_height * 2), CELL_ASPECT_RATIO override),
  WGSL unlit+lambert pipelines, backface culling instead of depth
  buffer (convex cube only - documented limitation).
- D: cell conversion (None mode = full-block per pixel; Cpu mode =
  quadrant-glyph algorithm ported from supersampling.wgsl - this is the
  Phase 2 oracle; Gpu aliases Cpu until the compute pass lands),
  Three_cli_renderer facade (create/init/draw_scene/set_active_camera/
  set_background_color/set_size/toggle_super_sampling/render_stats/
  destroy), Memory-renderer snapshot tests, spinning-cube demo.

## webgpu.h v29.0.1.1 ABI facts (verified against pinned header)

Shader stages: Vertex=0x1, Fragment=0x2, Compute=0x4 (int64).
ColorWriteMask_All=0xF. IndexFormat_Uint16=1. BufferBindingType_Uniform=2.
VertexStepMode_Vertex=1. PrimitiveTopology_TriangleList=4.
CullMode_Back=3. FrontFace_CCW=1. VertexFormat_Float32x2=0x1D,
Float32x3=0x1E. SType_ShaderSourceWGSL=2.

WGSL source attaches via chained struct:
`WGPUShaderSourceWGSL { chain{next,sType=WGPUSType_ShaderSourceWGSL},
code:StringView }` hung off ShaderModuleDescriptor.nextInChain.

RenderPipelineDescriptor fields, in order: nextInChain, label, layout,
vertex:VertexState, primitive:PrimitiveState, depthStencil(nullable),
multisample:MultisampleState{nextInChain,count=1,mask=0xF,alphaToCoverage},
fragment(nullable ptr to FragmentState).

VertexState: nextInChain, module, entryPoint:StringView, constantCount,
constants, bufferCount, buffers. FragmentState: same shape but
targetCount/targets. VertexBufferLayout: nextInChain, stepMode,
arrayStride(u64), attributeCount, attributes. VertexAttribute:
nextInChain, format, offset(u64), shaderLocation(u32). ColorTargetState:
nextInChain, format, blend(nullable), writeMask(u64).

BindGroupLayoutEntry (large struct - zero fill everything):
nextInChain, binding(u32), visibility(u64), bindingArraySize(u32),
buffer{chain,type,hasDynamicOffset,minBindingSize}, sampler{...},
texture{...}, storageTexture{...}.

PipelineLayoutDescriptor: nextInChain, label, bindGroupLayoutCount,
bindGroupLayouts, immediateSize(u32). BindGroupDescriptor: nextInChain,
label, layout, entryCount, entries. BindGroupEntry: nextInChain,
binding(u32), buffer, offset(u64), size(u64; WGPU_WHOLE_SIZE sentinel),
sampler, textureView.

Draw path: renderPassEncoderSetPipeline / SetBindGroup(index, group, 0,
NULL) / SetVertexBuffer(slot, buf, 0, size) / DrawIndexed(count, 1, 0,
baseVertex=0, 0). Uniform upload: wgpuQueueWriteBuffer(queue, buffer,
offset, data, size).

Diagnostics hooks: WGPUDeviceDescriptor ends with deviceLostCallbackInfo
and uncapturedErrorCallbackInfo ({nextInChain, callback, userdata1,
userdata2}); WGPUUncapturedErrorCallback signature = (device, type:
WGPUErrorType, message:StringView, ud1, ud2). wgpu.h extensions:
wgpuSetLogCallback(callback, userdata) + wgpuSetLogLevel(level)
(Off=0..Trace=5); WGPULogCallback = (level, message:StringView, ud).

Request adapter statuses: Success=1, CallbackCancelled=2,
Unavailable=3, Error=4. (Earlier confusion: 3 is Unavailable.)

## Known wgpu-native v29.0.1.1 quirks (workarounds are load-bearing)

1. Buffer-map completion is NOT wired into the futures API: awaiting map
   callbacks through wgpuInstanceWaitAny panics "not implemented" under
   both wait modes. Maps register WaitAnyOnly and are driven by the
   wgpuDevicePoll extension (non-blocking pump + 10 s monotonic deadline
   -> structured Map_failed). Never "restore" WaitAny for maps.
2. Descriptors whose StringView fields are {NULL,0} misparse downstream
   (validation sees garbage in the NEXT field, e.g. TextureUsages(0x0)).
   Every descriptor label must be a real non-empty string.
3. Both reproduced against pure C drivers before adoption; upstream
   reports still owed.

## Repo conventions that bit once already

- floatarray has NO `.()` indexing sugar - use Float.Array.get/set.
- No polymorphic compare: Int.equal/compare, Float.compare everywhere
  (warnings-as-errors catches some, review catches the rest).
- Trailing `;` on the last statement of a let-binding swallows the next
  `let` as a sequence expression - produces confusing downstream syntax
  errors (cost an hour in quaternion.ml).
- Module dependency cycles: Matrix4 <-> Quaternion broke dune; keep
  dependencies one-directional (Quaternion writes into caller-owned
  storage via unit-returning functions).
- Never delete _build subdirectories manually (corrupts digest db ->
  forced a second dune clean). Disk pressure: remove stale
  _build-* investigation dirs instead.
- windtrap traps stdout/stderr per test; read captured output from
  _build/_tests/<suite>/<hash>/<test_name>.output, or write to an
  explicit file for live tracing.
- Apple /usr/bin/patch rejects git-style patch preamble; house patches
  are bare unified diffs with paths relative to the zig source dir.
- Parallel agent works in opentui-core concurrently: never stage
  agents.md, terminal-palette-detection/, or their commits; verify
  staged paths belong to this task only.

## Verified formulas (three.js r177 source, numerically checked)

setFromEuler XYZ (half-angle c/s per axis):
x=s1*c2*c3 + c1*s2*s3; y=c1*s2*c3 - s1*c2*s3; z=c1*c2*s3 + s1*s2*c3;
w=c1*c2*c3 - s1*s2*s3.

setFromRotationMatrix branches use m_ij = R[i][j] with flat index
j*4+i: trace>0 -> x=(m32-m23)/s etc.; dominant-diagonal branches as in
three.js Quaternion.js r177 (port verbatim, do not re-derive).

Perspective (RH, WebGPU depth [0..1] note: our Matrix4.perspective maps
depth [-1..1] like OpenGL - VERIFY before pipelines land; WebGPU wants
[0..1], so z-map must be adjusted when the first cube renders).

Cell emission converts linear working space to sRGB bytes once at cell
write (intentional divergence from reference byte truncation; mid-gray
test locks the value).
