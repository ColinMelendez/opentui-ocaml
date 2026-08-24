(* Phase-1 uniform block shared by both pipelines, 48 floats = 192 bytes,
   matching the layout recorded in the three-renderer working notes:
   mvp(16) model(16) color(4) light_dir(4) light_color(4) ambient(4).
   Light data is precomputed on the CPU; the lambert fragment shader only
   evaluates albedo * (ambient.rgb * ambient.a + light.rgb * NdotL). *)

let uniform_floats = 48

let slot_mvp = 0

let slot_model = 16

let slot_color = 32

let slot_light_dir = 36

let slot_light_color = 40

let slot_ambient = 44

let header =
  {wgsl| struct Uniforms {
           mvp : mat4x4<f32>,
           model : mat4x4<f32>,
           color : vec4<f32>,
           light_dir : vec4<f32>,
           light_color : vec4<f32>,
           ambient : vec4<f32>,
         };
         @group(0) @binding(0) var<uniform> u : Uniforms;
         struct VSOut {
           @builtin(position) pos : vec4<f32>,
           @location(0) world_normal : vec3<f32>,
         };
         @vertex fn vs_main(@location(0) pos : vec3<f32>,
                            @location(1) nrm : vec3<f32>) -> VSOut {
           var out : VSOut;
           out.pos = u.mvp * vec4<f32>(pos, 1.0);
           out.world_normal = (u.model * vec4<f32>(nrm, 0.0)).xyz;
           return out;
         }
  |wgsl}

let wgsl_unlit =
  header ^ {wgsl|
         @fragment fn fs_main(in : VSOut) -> @location(0) vec4<f32> {
           return u.color;
         }
  |wgsl}

let wgsl_lambert =
  header ^ {wgsl|
         @fragment fn fs_main(in : VSOut) -> @location(0) vec4<f32> {
           let n = normalize(in.world_normal);
           let diffuse = max(dot(n, u.light_dir.xyz), 0.0);
           return vec4<f32>(
             u.color.rgb * (u.ambient.rgb * u.ambient.a
                            + (u.light_color.rgb * diffuse)),
             u.color.a);
         }
  |wgsl}
