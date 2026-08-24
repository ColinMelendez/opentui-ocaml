# Phase 2 working state

Non-normative progress notes for phase 2 (supersampling compute pass +
materials parity). Same purpose as the phase 1 file: let any fresh
session resume without re-deriving decisions. Phase 1 landed as ee48256
(slice C) and 1c4a4dc (slice D); its notes now live in
phase1-progress.md and the shipped code.

## Locked scope (from feature.md)

1. Ported WGSL compute pass produces cells IDENTICAL to the CPU oracle
   (`Three.Cell_conversion`) on shared fixtures. This is the acceptance
   gate - build the comparison harness first or early.
2. Phong materials, point lights, emissive terms, textured materials
   with wrap/filter controls, snapshot-tested.
3. Stats overlay parity (MapAsync / SS-Draw splits, algorithm line),
   super-sample toggling behavior (done in phase 1), save-to-file via
   core Image PNG encode (risk 15).

## Where things stand

MILESTONE 2 LANDED (materials/lighting/algorithm/stats/save; working
tree at time of writing):

- Uniform block v2: 92 floats / 368 B. Slots: mvp@0 model@16 color@32
  light_dir@36 light_color@40 ambient@44 specular_shininess@48
  emissive_intensity@52 point_positions@56 point_colors@72
  camera_position@88. One layout shared by unlit/lambert/phong.
- Mesh_phong_material: Blinn-Phong half-vector specular with SEPARATE
  diffuse/specular accumulators (albedo scales ONLY diffuse - an early
  draft multiplied spec by albedo and killed highlights on black).
  Emissive adds unconditionally (survives zero lights).
- PointLight: up to 4 visible lights, scene order, legacy windowed
  squared falloff over `distance` (cutoff<=0 disables attenuation -
  distance=0 does NOT mean "falloff to zero").
- Pre-squeezed sampleAlgo ported CPU-side (Cell_conversion ~algorithm)
  and GPU-side (Engine.set_super_sample_algorithm rewrites params);
  facade accessors + stats line; oracle test covers it.
- Stats overlay: Render/Readback/Total Draw/SS Draw/SuperSample/
  Algorithm lines at the reference offset.
- png.ml: stored-deflate PNG writer (CRC32 table, Adler32 BE, filter-0
  rows); Facade.save_to_file writes render-dims frame. Verified by
  decoding through Core.Image (dims + clear-color corner bytes).
- Cursor-agent review findings all fixed: phong teardown leak, orphan ss
  shader in create, dead shadowed lambert binding, facade init/Cpu-path
  algorithm sync, point-specular attenuation, catch-all narrowing,
  unused setters removal.

MILESTONE 3 LANDED (textured materials; working tree at time of
writing) - PHASE 2 SCOPE COMPLETE:

- wgpu: create_sampler (wrap/filter controls), material bind-group
  layout (uniform+texture+filtering sampler), textured render pipeline
  (stride 32: pos@0 nrm@12 uv@24 loc2), data_texture upload path.
- Three.Texture (CPU RGBA + wrap_s/wrap_t/filter) and Texture_utils
  generators (checkerboard, horizontal/vertical/radial gradient,
  deterministic integer-hash octave noise).
- Material.map: engine keys GPU texture+sampler on texture INSTANCE;
  unmapped meshes share a 1x1 white fallback gated by flags.x in WGSL
  surface_albedo; first-frame bind bug (fresh entries skipped map sync)
  caught by test and fixed.
- Vertex layout is now stride 32 everywhere via the textured pipeline
  stub; BoxGeometry emits per-face UVs.

Second cursor review found 5 defects, all fixed: unlit missing
shared_body (undefined fn risk across backends), phong diffuse ignoring
the map, cached-sampler double-free via entry teardown, geometry-swap
path skipping map sync, empty-payload zlib block.

Test gap still open: phong point-light specular under attenuation; wrap/
repeat modes are config-tested only (Box UVs stay within 0..1).

## Where things stood before milestone 2

COMPUTE PASS MILESTONE LANDED:

- opentui-wgpu gained compute infrastructure: create_compute_pipeline,
  create_supersampling_bind_group_layout (texture + rw-storage + uniform),
  create_compute_bind_group, dispatch_compute_pass (pass + buf-to-buf copy
  + submit), create_copy_readback (raw byte staging, no 256 rule),
  write_texture_bytes (queueWriteTexture; caller pads rows),
  render_target_texture accessor, buffer_usage_storage,
  texture_usage_{texture_binding,copy_destination}. Render targets now
  carry TEXTURE_BINDING|COPY_DST too.
- Three.Shaders.wgsl_supersampling is a verbatim port of the reference
  (WORKGROUP_SIZE=4 substituted).
- Engine owns supersampler state (bgl/pipeline/params/storage/readback/
  staging) keyed to target dims; set_super_sample rebuilds on resize;
  stage() branches Gpu -> dispatch+map+copy of cell records;
  last_cells/last_cell_grid expose raw output.
- Facade `Gpu` mode is REAL now (no longer aliases Cpu); decode goes
  through Cell_conversion.write_gpu_records with the compute-grid pitch.
- ACCEPTANCE: test_supersampling.ml runs both paths over shared fixtures
  (flat, gradient, checkerboard, alpha-blend, odd width, determinism)
  and requires bit-equal Owned_buffer snapshots. All pass on lavapipe.

Remaining phase-2 scope: Phong/point lights/emissive/textured materials,
stats overlay MapAsync/SS-Draw splits + algorithm line, save-to-file
(risk 15), pre-squeezed sampleAlgo variant (shader has it; CPU oracle
does not - decide port vs documented omission).

## Debug lessons that cost real time (do not relearn)

- wgpu VALIDATION ERRORS ARE RUST PANICS: the crash looked like SIGBUS
  (138). First move when a GPU test dies weirdly: read the trapped
  per-test output under _build/_tests/<suite>/<hash>/<test>.output -
  the panic text was there the whole time.
- Texture usage enum values DIFFER from buffer usage values:
  texture COPY_SRC=0x1, COPY_DST=0x2 (buffer versions are 0x4/0x8).
  Always use the Native getters, never literals.
- Uniform BINDING size must be >= the shader struct size INCLUDING its
  padding word: SuperSamplingParams is 16B (three u32s + _padding);
  binding a 12B buffer panics the queue submit.
- Compute record layout pitch is the COMPUTE grid width ((w+1)/2), not
  the output grid; they differ on odd render sizes. Engine exposes
  last_cell_grid for exactly this.
- OCaml externals take at most 5 positional args on native - bundle the
  rest in a tuple (C side reads Field(options,i)).
- CAMLparam5 is the C-side max likewise.
- windtrap traps stdout/stderr, so C-level crashes silently eat eprintf
  traces; use file traces OUTSIDE the sandboxed streams, or better, read
  the trapped outputs after the fact.
- Temporary open_out_gen calls MUST pass real perms (0o644); passing 0
  creates mode-000 files whose later opens cascade confusing failures.

## Compute-pass requirements discovered up front

opentui-wgpu currently supports only RENDER pipelines. The pass needs:

- Compute pipeline creation: WGPUComputePipelineDescriptor{nextInChain,
  label, layout, compute:ProgrammableStage{nextInChain, module,
  entryPoint:StringView, constantCount, constants}}.
- Bind group layout entry kinds beyond uniform: a TEXTURE binding
  (textureLoad -> no sampler; WGPUTextureSampleType_Float=1?
  VERIFY against pinned webgpu.h; viewDimension 2d) and STORAGE buffers
  (buffer type WGPUBufferBindingType_Storage = 3? VERIFY; read-only vs
  read_write matters - WGSL declares var<storage, read_write>).
- New buffer usage flags: STORAGE (0x80 expected - VERIFY),
  TEXTURE_BINDING (0x4? VERIFY), COPY_SRC on storage output (have it).
- Render targets must gain TEXTURE_BINDING usage so the frame texture
  binds as the compute input (create_render_target currently sets
  RENDER_ATTACHMENT|COPY_SOURCE only).
- Compute pass encoding: encoderBeginComputePass({label}), setPipeline,
  setBindGroup(0, group, 0, NULL), dispatchWorkgroups(x,y,1), end.
  Cell counts: (width+1)/2 x (height+1)/2; WORKGROUP_SIZE 4x4 ->
  dispatch ceil(cells/4).
- Buffer-to-buffer copy (storage output -> map-read readback): new
  encoderCopyBufferToBuffer stub.
- 48-byte cell record layout out of the compute buffer:
  bg vec4 (16B), fg vec4 (16B), char u32 (4B), 3x padding u32.

## Oracle contract (how acceptance will be tested)

Shared fixture = stride-stripped RGBA byte string (linear bytes).
CPU side: Cell_conversion.write_quadrants into one Owned_buffer.
GPU side: upload fixture to a texture, run the compute pass, decode the
48-byte records, apply Cell_conversion.linear_to_srgb_byte at cell
write (the locked color-space divergence happens OUTSIDE the algorithm;
the WGSL math itself stays linear). Assert bit-equal glyph/color words
through Owned_buffer.snapshot probe comparison (see
test_cell_conversion.ml's expect_single_cell pattern for API-level
encoding checks without native layout knowledge).

Fixtures must cover: all-dark, all-light-ish (ties), single-quadrant,
column/row patterns, alpha-blend cases (alpha != 255), odd dimensions
(out-of-bounds getPixelColor returns black opaque - port that).

## Reference facts already extracted (supersampling.wgsl, canvas.ts)

- quadrantChars table index = bits: space, U+2597..U+259F family,
  see cell_conversion.ml quadrant_chars (ported & tested).
- blendColors: outAlpha = a1+a2-a1*a2; rgb weighted; zero-alpha guards.
- averageColorsWithAlpha = blend(blend(p0,p1), blend(p2,p3)).
- closestColorIndex uses <= (ties go DARK -> bit set).
- Max-distance pair scan is i<j sequential with strict > (first pair
  wins ties).
- sampleAlgo 1 (pre-squeezed) exists in the shader; reference defaults
  to STANDARD(0). Port variant 1 too or document omission - decide at
  implementation.
- CLICanvas.readPixelsIntoBuffer order: GPU path runs compute AFTER
  switchTextures(); None/CPU paths map the plain readback.

## Materials-parity notes (for later slices)

Reference MeshPhongMaterial demo usage: map, specularMap, normalMap,
emissiveMap, shininess, specular, emissive, emissiveIntensity.
PointLight(color, intensity, distance). Uniform block grows beyond the
phase-1 192B layout - plan slot layout before writing WGSL; keep one
uniform struct per mesh.

## Conventions that keep biting (carried from phase 1)

See phase1-progress.md "Repo conventions that bit once already" -
still true: no polymorphic compare, trailing-semicolon swallowing,
module acyclicity, ref-vs-record assignment, dune lock contention with
parallel agents (wait, never remove lock), stale-cmx fix by real
content change not clean, windtrap output under _build/_tests.
