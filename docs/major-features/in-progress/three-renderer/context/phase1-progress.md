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

- B: DONE (commits 1241150, f3f9ed5). Pipeline/draw/diagnostics stubs
  shipped; OCaml-driven triangle renders exact pixels in CI; risk 16b
  capture delivered; risk 16c retired (root causes: missing copy call
  in submit_draw_frame orchestration + Double_field-on-boxed-tuple in
  draw stub clear color).
- C: DONE (this working tree, uncommitted at time of writing). Scene
  graph (`Object3d` unified node record + payload variant: Group,
  Scene_root, Mesh, Perspective_camera, Directional/Ambient_light),
  `Box_geometry` per-face normals, `Mesh_basic/lambert_material`,
  lights, `Perspective_camera`, WGSL unlit+lambert pipelines, and
  `Three.Engine` render core. Suites: scene-graph units (9), box
  geometry winding/normals (4), GPU integration (7: unlit, head-on
  lambert, pitched two-class shading, multi-mesh, determinism,
  visibility pruning, resize). Backface culling instead of depth
  buffer remains the documented convex-only limitation.
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
  errors (cost an hour in quaternion.ml, struck AGAIN in
  test_render.ml's run_frame where the error surfaces as a generic
  EOF syntax error far from the cause).
- Module dependency cycles: Matrix4 <-> Quaternion broke dune; keep
  dependencies one-directional. Vector3.apply_quaternion had to become
  an inlined private helper in object3d.ml (Vector3 -> Quaternion would
  cycle with Quaternion.from_axis_angle's axis : Vector3.t).
- Ref vs record: `r <- v` on a ref cell is parsed as record-field set
  and fails confusingly ("not an instance variable"); refs want `:=`.
- Never delete _build subdirectories manually (corrupts digest db ->
  forced a second dune clean). Disk pressure: remove stale
  _build-* investigation dirs instead.
- If dune reports "inconsistent assumptions over interface" after a
  killed build and touching sources does not clear it, appending a
  real content change to the stale unit forces recompilation without
  violating the no-clean rule.
- windtrap traps stdout/stderr per test; read captured output from
  _build/_tests/<suite>/<hash>/<test_name>.output, or write to an
  explicit file for live tracing.
- Apple /usr/bin/patch rejects git-style patch preamble; house patches
  are bare unified diffs with paths relative to the zig source dir.
- Parallel agent works in opentui-core concurrently: never stage
  agents.md, terminal-palette-detection/, or their commits; verify
  staged paths belong to this task only. Their in-flight edits can
  break our builds transiently (unbound values mid-edit); wait and
  retry rather than "fixing" their half-finished code.

## Verified formulas (three.js r177 source, numerically checked)

setFromEuler XYZ (half-angle c/s per axis):
x=s1*c2*c3 + c1*s2*s3; y=c1*s2*c3 - s1*c2*s3; z=c1*c2*s3 + s1*s2*c3;
w=c1*c2*c3 - s1*s2*s3.

Quaternion.setFromRotationMatrix SHEPPERD NAMING TRAP: three.js's local
`m11 m12 m13 / m21 ...` names are SEQUENTIAL element labels (m11=te[0],
m12=te[4], m13=te[8], ...), NOT matrix indices. Branch conditions use
the labels; off-diagonal pairs must be read through the label mapping
(e.g. their `w=(m32-m23)` means te[6]-te[9]). Misreading them as matrix
indices produced wrong dominant-diagonal arms twice in one day; final
arms are verified against pure X/Y/Z rotations of 150 degrees (whose
trace <= 0 forces the non-trace arms) and round-trip tested.

setFromRotationMatrix branches use m_ij = R[i][j] with flat index
j*4+i: trace>0 -> x=(m32-m23)/s etc.; dominant-diagonal branches as in
three.js Quaternion.js r177 (port verbatim, do not re-derive).

Perspective (RH, WebGPU depth [0..1] note: our Matrix4.perspective maps
depth [-1..1] like OpenGL - VERIFY before pipelines land; WebGPU wants
[0..1], so z-map must be adjusted when the first cube renders).

Cell emission converts linear working space to sRGB bytes once at cell
write (intentional divergence from reference byte truncation; mid-gray
test locks the value).


## Preserved investigation body (unlit-triangle draw test)

Preserved verbatim while the silent-empty-frame question stays open; the committed suite skips this test loudly. Restore under `test ... (fun () -> ...)` once root-caused.

```ocaml
      ignore
        (fun () ->
          let device = take_device "pipeline draw" (Wgpu.create_device ()) in
          (* earlier tests may have deliberately provoked validation
             errors; clear the slate so only THIS step's problems show *)
          ignore (Wgpu.drain_diagnostics ~max:64 ());
          let wgsl =
            {wgsl| struct Uniforms {
                      mvp : mat4x4<f32>,
                      model : mat4x4<f32>,
                      color : vec4<f32>,
                    };
                    @group(0) @binding(0) var<uniform> u : Uniforms;
                    struct VSOut {
                      @builtin(position) pos : vec4<f32>,
                      @location(0) normal : vec3<f32>,
                    };
                    @vertex fn vs_main(@location(0) pos : vec3<f32>,
                                       @location(1) nrm : vec3<f32>) -> VSOut {
                      var out : VSOut;
                      out.pos = u.mvp * vec4<f32>(pos, 1.0);
                      out.normal = nrm;
                      return out;
                    }
                    @fragment fn fs_main(in : VSOut) -> @location(0) vec4<f32> {
                      return vec4<f32>(0.0, 1.0, 0.0, 1.0);
                    }
                    |wgsl}
          in
          let width = 8 and height = 8 in
          let target =
            expect_ok (Wgpu.create_render_target device ~width ~height)
          in
          let stride = Wgpu.readback_stride ~width in
          let readback =
            expect_ok (Wgpu.create_readback device ~stride ~rows:height)
          in
          let staging = make_staging (Wgpu.readback_size readback) in
let shader =
            expect_ok (Wgpu.create_shader_module device ~wgsl)
          in
          let bgl = expect_ok (Wgpu.create_uniform_bind_group_layout device) in
          let playout = expect_ok (Wgpu.create_pipeline_layout device bgl) in
          let pipeline =
            expect_ok
              (Wgpu.create_render_pipeline device ~layout:playout ~shader
                 ~vs_entry:"vs_main" ~fs_entry:"fs_main"
                 ~target_format:Wgpu.texture_format_rgba8_unorm)
          in

          (* full-screen triangle covering the 8x8 target *)
          let vertices =
            Float.Array.of_list
              [ -1.0; -1.0; 0.2;  0.0; 0.0; 0.0;
                 3.0; -1.0; 0.2;  0.0; 0.0; 0.0;
                -1.0;  3.0; 0.2;  0.0; 0.0; 0.0 ]
          in
          let indices = [| 0; 1; 2 |] in
          let vertex_bytes = Wgpu.pack_f32_le vertices in
          let index_bytes = Wgpu.pack_indices_u16 indices in
          let vertex_buffer =
            expect_ok
              (Wgpu.create_buffer device
                 ~size:(String.length vertex_bytes)
                 ~usage:(Int64.logor Wgpu.buffer_usage_vertex
                           Wgpu.buffer_usage_copy_destination))
          in
          let index_buffer =
            expect_ok
              (Wgpu.create_buffer device
                 ~size:(Wgpu.align4 (String.length index_bytes))
                 ~usage:(Int64.logor Wgpu.buffer_usage_index
                           Wgpu.buffer_usage_copy_destination))
          in
          let uniform_size = 160 in
          let uniform_buffer =
            expect_ok
              (Wgpu.create_buffer device ~size:uniform_size
                 ~usage:(Int64.logor Wgpu.buffer_usage_copy_destination
                           Wgpu.buffer_usage_uniform))
          in
          expect_ok
            (Wgpu.write_buffer_string device vertex_buffer ~offset:0
               vertex_bytes);
          expect_ok
            (Wgpu.write_buffer_string device index_buffer ~offset:0
               index_bytes);
          (* identity mvp + model, opaque red *)
          let identity = [| 1.0; 0.0; 0.0; 0.0; 0.0; 1.0; 0.0; 0.0;
                            0.0; 0.0; 1.0; 0.0; 0.0; 0.0; 0.0; 1.0 |]
          in
          let uniforms = Float.Array.make 40 0.0 in
          Array.iteri (fun i v -> Float.Array.set uniforms i v) identity;
          Array.iteri
            (fun i v -> Float.Array.set uniforms (16 + i) v)
            identity;
          Float.Array.set uniforms 32 1.0;
          Float.Array.set uniforms 34 0.0;
          Float.Array.set uniforms 35 0.0;
          Float.Array.set uniforms 36 1.0;
          expect_ok
            (Wgpu.write_buffer_string device uniform_buffer ~offset:0
               (Wgpu.pack_f32_le uniforms));
          let group =
            expect_ok
              (Wgpu.create_uniform_bind_group device bgl uniform_buffer
                 ~size:uniform_size)
          in


          let dbg_result = Wgpu.debug_triangle device in
          ignore (Wgpu.debug_triangle device);
          let post_logs =
            String.concat " || " (Wgpu.drain_diagnostics ~max:64 ())
          in
          if dbg_result <> 255 then
            fail
              (Printf.sprintf "C probe center=%d logs=[%s]" dbg_result
                 post_logs);
          expect_ok
            (Wgpu.submit_draw_frame device ~target ~readback
               ~clear:(0.0, 1.0, 0.0, 1.0)
               ~draw:
                 { pipeline;
                   group;
                   vertex_buffer;
                   vertex_size = String.length vertex_bytes;
                   index_buffer;
                   index_size = String.length index_bytes;
                   index_count = Array.length indices }
               ());
          expect_ok (Wgpu.map_read device readback);
          expect_ok (Wgpu.copy_mapped readback staging.pixels);
          Wgpu.unmap readback;

          let dump = Buffer.create 64 in
          for row = 0 to height - 1 do
            for column = 0 to width - 1 do
              let base = (row * stride) + (column * 4) in
              Buffer.add_string dump
                (Printf.sprintf "[%d,%d]=%02x%02x%02x%02x " row column
                   (Char.code (Bigarray.Array1.get staging.pixels base))
                   (Char.code (Bigarray.Array1.get staging.pixels (base + 1)))
                   (Char.code (Bigarray.Array1.get staging.pixels (base + 2)))
                   (Char.code (Bigarray.Array1.get staging.pixels (base + 3))))
            done;
            Buffer.add_char dump '\n'
          done;
          let diags = String.concat " || " (Wgpu.drain_diagnostics ~max:64 ()) in
          if true then
            fail
              ("FRAME DUMP:\n" ^ Buffer.contents dump ^ "\nDIAGS: "
               ^ (if String.equal diags "" then "(none)" else diags));
          expect_pixel ~row:(height / 2) ~stride ~width
            ~column:(width / 2) ~pixels:staging.pixels
            ~expected:[ 255; 0; 0; 255 ];

          if List.exists
               (fun line ->
                 String.length line >= 18
                 && String.sub line 0 18 = "uncaptured gpu err")
               (Wgpu.drain_diagnostics ())
          then fail "uncaptured GPU errors were recorded";

          Wgpu.destroy_bind_group group;
          Wgpu.destroy_bind_group_layout bgl;
          Wgpu.destroy_pipeline_layout playout;
          Wgpu.destroy_shader_module shader;
          Wgpu.destroy_render_pipeline pipeline;
          Wgpu.destroy_buffer vertex_buffer;
          Wgpu.destroy_buffer index_buffer;
          Wgpu.destroy_buffer uniform_buffer;
          Wgpu.destroy_readback readback;
          Wgpu.destroy_render_target target;
          Wgpu.destroy_device device);
```

## Slice C/D specifics (everything needed to resume without re-research)

Landed with slice C (verify against code, which is now the source of
truth):

- Uniform block: 48 floats = 192 B. Slots (float index): mvp@0,
  model@16, color@32, light_dir@36, light_color@40, ambient@44.
  WGSL struct mirrors exactly; all fields vec4/mat4 so no padding
  surprises. CPU precomputes L = normalize(light.worldPos -
  target.worldPos), folds directional intensity into light_color.rgb,
  and accumulates ALL visible ambient lights into ambient.rgb/a where
  a = summed intensity. AMBIENT GOTCHA: color channels ride untouched;
  intensity lives ONLY in the alpha slot - the shader multiplies
  ambient.rgb * ambient.a once. Pre-multiplying color by intensity on
  the CPU double-applies it (cost one debugging round: gray cube read
  byte 8 instead of 32).
- Rotation sync: Object3D keeps euler and quaternion consistent lazily
  at matrix-build time (compare euler against synced_rotation cache;
  differ -> Quaternion.set_from_euler). Divergence vs three.js eager
  callbacks: reading quaternion right after writing euler (without an
  update between) diverges; the orientation methods (rotate_on_axis,
  translate_on_axis, look_at) call sync_rotation first so method
  sequences behave like three.js regardless of render timing.
- look_at feeds Quaternion.from_euler_matrix, which reads an
  ORIENTATION block - Matrix4.look_at writes the VIEW convention
  (transposed basis), so object3d transposes the 3x3 back before
  extraction. Off-axis camera test (camera on +X looking at origin)
  catches regressions; the straight-on case hides the bug entirely.
- rotate_on_axis is deliberately pure-local (post-multiply only), NOT
  three.js r177's parent-compensated premultiply; documented in
  object3d.mli. Parented test pins child-local axis behavior.
- Engine (`Three.Engine`, public phase-1 rendering core): owns device +
  target + readback + staging + pipelines + per-mesh GPU cache keyed by
  physical node identity. render = update_matrix_world -> camera view
  refresh -> collect visible meshes (prune invisible subtrees) ->
  stable front-to-back sort by distance^2 to camera translation ->
  gather lights (first visible directional only - single uniform slot)
  -> pack uniforms + queue writes -> submit_draw_frame -> map/copy/
  unmap. snapshot() strips stride padding into width*height*4 bytes.
  resize() rebuilds target/readback/staging in place.
- wgpu reshape for slice C: submit_draw_frame takes `draws : list`
  encoded as multiple indexed draws inside ONE render pass; empty list
  = clear-only frame; submit_clear_frame deleted (folded in).
  wgpu.mli now exports module Native_token (downstream needs to name
  buffer types stored in engine mesh entries).
- GPU test expected values (lavapipe-verified, +/-2 tolerance):
  head-on lambert albedo .5, ambient white*.25, dir white*1 from
  z=5: front face byte 159 (=0.625 linear), pitched 30deg gives two
  classes 142 (front) / 96 (top), unlit hex colors encode directly.

Three_cli_renderer facade must expose (reference names):
create/init/draw_scene/set_active_camera/set_background_color/
set_size/toggle_super_sampling/render_stats/destroy.
Options: width, height, ?focal_length (FOV = 2*atan(H/(2*focal))
degrees when given), ?background_color, ?super_sample (None|Cpu|Gpu;
Gpu aliases Cpu until phase 2 compute pass - documented divergence),
?alpha. Camera default position (0,0,3) lookAt origin, near 0.1 far
1000. Aspect = terminal_width / (terminal_height * 2) unless
CELL_ASPECT_RATIO env set (risk item 16 wants a construction test).

Snapshot tests: Renderer.create ~output:Memory + Frame_buffer renderable
+ pre_render driver calling draw_scene; assert Owned_buffer.snapshot
cell structure (glyph/color classes, not exact RGB everywhere);
determinism check = two identical renders bit-equal.

Demo: packages/opentui-three/examples/spinning_cube_demo.ml using the
examples/lib App.run pattern (see grayscale_buffer_demo.ml):
Frame_buffer renderable + pre_render tick rotating cube.rotation.y/x,
live lease, standalone keys for exit.

Cell conversion (Cpu mode) port of supersampling.wgsl quadrant
algorithm: per 2x2 block pick two most RGB-distant samples, order by
luminance (0.2126R+0.7152G+0.0722B), quadrant bits TL=8 TR=4 BL=2 BR=1
-> glyph space/U2596-U25FF family; all-dark/all-light use averaged
colors with alpha blending. None mode: full-block per pixel.
