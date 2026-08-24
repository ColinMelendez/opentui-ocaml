(* Phase-2 uniform block shared by all pipelines, 92 floats = 368 bytes.
   Offsets (float slots): mvp@0 model@16 color@32 light_dir@36
   light_color@40 ambient@44 specular_shininess@48 emissive_intensity@52
   point_positions@56 (4x vec4: xyz + distance cutoff) point_colors@72
   (4x vec4) camera_position@88. Lambert ignores the phong-only fields;
   unlit ignores lighting entirely - one layout, three entry sets. *)

let uniform_floats = 96

let slot_mvp = 0

let slot_model = 16

let slot_color = 32

let slot_light_dir = 36

let slot_light_color = 40

let slot_ambient = 44

let slot_specular_shininess = 48

let slot_emissive_intensity = 52

let slot_point_positions = 56

let slot_point_colors = 72

let slot_camera_position = 88

let slot_flags = 92

let max_point_lights = 4

let wgsl_uniforms =
  {wgsl| struct Uniforms {
           mvp : mat4x4<f32>,
           model : mat4x4<f32>,
           color : vec4<f32>,
           light_dir : vec4<f32>,
           light_color : vec4<f32>,
           ambient : vec4<f32>,
           specular_shininess : vec4<f32>,
           emissive_intensity : vec4<f32>,
           point_pos : array<vec4<f32>, 4>,
           point_color : array<vec4<f32>, 4>,
           camera_position : vec4<f32>,
           flags : vec4<f32>,
         };
         @group(0) @binding(0) var<uniform> u : Uniforms;
         @group(0) @binding(1) var t_albedo : texture_2d<f32>;
         @group(0) @binding(2) var t_sampler : sampler;
  |wgsl}

let header =
  wgsl_uniforms ^ {wgsl|
         struct VSOut {
           @builtin(position) pos : vec4<f32>,
           @location(0) world_normal : vec3<f32>,
           @location(1) world_pos : vec3<f32>,
           @location(2) uv : vec2<f32>,
         };
         @vertex fn vs_main(@location(0) pos : vec3<f32>,
                            @location(1) nrm : vec3<f32>,
                            @location(2) uv : vec2<f32>) -> VSOut {
           var out : VSOut;
           let world = u.model * vec4<f32>(pos, 1.0);
           out.pos = u.mvp * vec4<f32>(pos, 1.0);
           out.world_normal = (u.model * vec4<f32>(nrm, 0.0)).xyz;
           out.world_pos = world.xyz;
           out.uv = uv;
           return out;
         }
  |wgsl}

let shared_body =
  {wgsl|
         fn surface_albedo(uv : vec2<f32>) -> vec3<f32> {
           // flags.x gates the map; unmapped materials keep flat albedo
           // while still binding the shared white fallback texture.
           let mapped = textureSample(t_albedo, t_sampler, uv).rgb;
           return mix(u.color.rgb, u.color.rgb * mapped, u.flags.x);
         }
         fn point_attenuation(distance: f32, cutoff: f32) -> f32 {
           if (cutoff <= 0.0) {
             return 1.0;
           }
           let window = max(1.0 - distance / cutoff, 0.0);
           return window * window;
         }
  |wgsl}

let wgsl_unlit =
  header ^ shared_body ^ {wgsl|
         @fragment fn fs_main(in : VSOut) -> @location(0) vec4<f32> {
           return vec4<f32>(surface_albedo(in.uv), u.color.a);
         }
  |wgsl}

let wgsl_lambert =
  header ^ shared_body ^ {wgsl|
         @fragment fn fs_main(in : VSOut) -> @location(0) vec4<f32> {
           let n = normalize(in.world_normal);
           var lit = u.ambient.rgb * u.ambient.a;
           lit += u.light_color.rgb * max(dot(n, u.light_dir.xyz), 0.0);
           for (var i = 0; i < 4; i = i + 1) {
             let to_light = u.point_pos[i].xyz - in.world_pos;
             let d = length(to_light);
             if (d > 0.0001) {
               let l = to_light / d;
               let atten = point_attenuation(d, u.point_pos[i].w);
               lit += u.point_color[i].rgb * (atten * max(dot(n, l), 0.0));
             }
           }
           return vec4<f32>(surface_albedo(in.uv) * lit, u.color.a);
         }
  |wgsl}

let wgsl_phong =
  header ^ shared_body ^ {wgsl|
         @fragment fn fs_main(in : VSOut) -> @location(0) vec4<f32> {
           let n = normalize(in.world_normal);
           let view_dir = normalize(u.camera_position.xyz - in.world_pos);
           // Diffuse irradiance and specular radiance accumulate apart:
           // albedo scales only the diffuse part, matching three.js.
           var diffuse = u.ambient.rgb * u.ambient.a;
           var spec_acc = vec3<f32>(0.0, 0.0, 0.0);

           let dir_ndotl = max(dot(n, u.light_dir.xyz), 0.0);
           diffuse += u.light_color.rgb * dir_ndotl;
           if (u.specular_shininess.a > 0.0 && dir_ndotl > 0.0) {
             let half_dir = normalize(u.light_dir.xyz + view_dir);
             let spec = pow(max(dot(n, half_dir), 0.0),
                            u.specular_shininess.a);
             spec_acc += u.light_color.rgb * spec;
           }

           for (var i = 0; i < 4; i = i + 1) {
             let to_light = u.point_pos[i].xyz - in.world_pos;
             let d = length(to_light);
             if (d > 0.0001) {
               let l = to_light / d;
               let atten = point_attenuation(d, u.point_pos[i].w)
                 * max(dot(n, l), 0.0);
               if (atten > 0.0) {
                 diffuse += u.point_color[i].rgb * atten;
                 if (u.specular_shininess.a > 0.0) {
                   let half_dir = normalize(l + view_dir);
                   let spec = pow(max(dot(n, half_dir), 0.0),
                                  u.specular_shininess.a);
                   spec_acc +=
                     u.point_color[i].rgb * (atten * spec);
                 }
               }
             }
           }

           return vec4<f32>(
             (u.emissive_intensity.rgb * u.emissive_intensity.a)
             + (u.color.rgb * diffuse)
             + (u.specular_shininess.rgb * spec_acc),
             u.color.a);
         }
  |wgsl}

let wgsl_supersampling =
  {wgsl|struct CellResult {
      bg: vec4<f32>,      // Background RGBA (16 bytes)
      fg: vec4<f32>,      // Foreground RGBA (16 bytes)
      char: u32,          // Unicode character code (4 bytes)
      _padding1: u32,     // Padding (4 bytes)
      _padding2: u32,     // Extra padding (4 bytes)
      _padding3: u32,     // Extra padding (4 bytes) - total now 48 bytes (16-byte aligned)
  };

  struct CellBuffer {
      cells: array<CellResult>
  };

  struct SuperSamplingParams {
      width: u32,              // Canvas width in pixels
      height: u32,             // Canvas height in pixels
      sampleAlgo: u32,         // 0 = standard 2x2, 1 = pre-squeezed horizontal blend
      _padding: u32,           // Padding for 16-byte alignment
  };

  @group(0) @binding(0) var inputTexture: texture_2d<f32>;
  @group(0) @binding(1) var<storage, read_write> output: CellBuffer;
  @group(0) @binding(2) var<uniform> params: SuperSamplingParams;

  // Quadrant character lookup table (same as Zig implementation)
  const quadrantChars = array<u32, 16>(
      32u,      // ' '  - 0000
      0x2597u,  // ▗   - 0001 BR
      0x2596u,  // ▖   - 0010 BL
      0x2584u,  // ▄   - 0011 Lower Half Block
      0x259Du,  // ▝   - 0100 TR
      0x2590u,  // ▐   - 0101 Right Half Block
      0x259Eu,  // ▞   - 0110 TR+BL
      0x259Fu,  // ▟   - 0111 TR+BL+BR
      0x2598u,  // ▘   - 1000 TL
      0x259Au,  // ▚   - 1001 TL+BR
      0x258Cu,  // ▌   - 1010 Left Half Block
      0x2599u,  // ▙   - 1011 TL+BL+BR
      0x2580u,  // ▀   - 1100 Upper Half Block
      0x259Cu,  // ▜   - 1101 TL+TR+BR
      0x259Bu,  // ▛   - 1110 TL+TR+BL
      0x2588u   // █   - 1111 Full Block
  );

  const inv_255: f32 = 1.0 / 255.0;

  fn getPixelColor(pixelX: u32, pixelY: u32) -> vec4<f32> {
      if (pixelX >= params.width || pixelY >= params.height) {
          return vec4<f32>(0.0, 0.0, 0.0, 1.0); // Black for out-of-bounds
      }

      // textureLoad automatically handles format conversion to RGBA
      return textureLoad(inputTexture, vec2<i32>(i32(pixelX), i32(pixelY)), 0);
  }

  fn colorDistance(a: vec4<f32>, b: vec4<f32>) -> f32 {
      let diff = a.rgb - b.rgb;
      return dot(diff, diff);
  }

  fn luminance(color: vec4<f32>) -> f32 {
      return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
  }

  fn closestColorIndex(pixel: vec4<f32>, candA: vec4<f32>, candB: vec4<f32>) -> u32 {
      return select(1u, 0u, colorDistance(pixel, candA) <= colorDistance(pixel, candB));
  }

  fn averageColor(pixels: array<vec4<f32>, 4>) -> vec4<f32> {
      return (pixels[0] + pixels[1] + pixels[2] + pixels[3]) * 0.25;
  }

  fn blendColors(color1: vec4<f32>, color2: vec4<f32>) -> vec4<f32> {
      let a1 = color1.a;
      let a2 = color2.a;

      if (a1 == 0.0 && a2 == 0.0) {
          return vec4<f32>(0.0, 0.0, 0.0, 0.0);
      }

      let outAlpha = a1 + a2 - a1 * a2;
      if (outAlpha == 0.0) {
          return vec4<f32>(0.0, 0.0, 0.0, 0.0);
      }

      let rgb = (color1.rgb * a1 + color2.rgb * a2 * (1.0 - a1)) / outAlpha;

      return vec4<f32>(rgb, outAlpha);
  }

  fn averageColorsWithAlpha(pixels: array<vec4<f32>, 4>) -> vec4<f32> {
      let blend1 = blendColors(pixels[0], pixels[1]);
      let blend2 = blendColors(pixels[2], pixels[3]);

      return blendColors(blend1, blend2);
  }

  fn renderQuadrantBlock(pixels: array<vec4<f32>, 4>) -> CellResult {
      var maxDist: f32 = colorDistance(pixels[0], pixels[1]);
      var pIdxA: u32 = 0u;
      var pIdxB: u32 = 1u;

      for (var i: u32 = 0u; i < 4u; i++) {
          for (var j: u32 = i + 1u; j < 4u; j++) {
              let dist = colorDistance(pixels[i], pixels[j]);
              if (dist > maxDist) {
                  pIdxA = i;
                  pIdxB = j;
                  maxDist = dist;
              }
          }
      }

      let pCandA = pixels[pIdxA];
      let pCandB = pixels[pIdxB];

      var chosenDarkColor: vec4<f32>;
      var chosenLightColor: vec4<f32>;

      if (luminance(pCandA) <= luminance(pCandB)) {
          chosenDarkColor = pCandA;
          chosenLightColor = pCandB;
      } else {
          chosenDarkColor = pCandB;
          chosenLightColor = pCandA;
      }

      var quadrantBits: u32 = 0u;
      let bitValues = array<u32, 4>(8u, 4u, 2u, 1u); // TL, TR, BL, BR

      for (var i: u32 = 0u; i < 4u; i++) {
          if (closestColorIndex(pixels[i], chosenDarkColor, chosenLightColor) == 0u) {
              quadrantBits |= bitValues[i];
          }
      }

      // Construct result
      var result: CellResult;

      if (quadrantBits == 0u) { // All light
          result.char = 32u; // Space character
          result.fg = chosenDarkColor;
          result.bg = averageColorsWithAlpha(pixels);
      } else if (quadrantBits == 15u) { // All dark
          result.char = quadrantChars[15]; // Full block
          result.fg = averageColorsWithAlpha(pixels);
          result.bg = chosenLightColor;
      } else { // Mixed pattern
          result.char = quadrantChars[quadrantBits];
          result.fg = chosenDarkColor;
          result.bg = chosenLightColor;
      }
      result._padding1 = 0u;
      result._padding2 = 0u;
      result._padding3 = 0u;

      return result;
  }

  @compute @workgroup_size(4, 4, 1)
  fn main(@builtin(global_invocation_id) id: vec3<u32>) {
      let cellX = id.x;
      let cellY = id.y;
      let bufferWidthCells = (params.width + 1u) / 2u;
      let bufferHeightCells = (params.height + 1u) / 2u;

      if (cellX >= bufferWidthCells || cellY >= bufferHeightCells) {
          return;
      }

      let renderX = cellX * 2u;
      let renderY = cellY * 2u;

      var pixelsRgba: array<vec4<f32>, 4>;

      if (params.sampleAlgo == 1u) {
          let topColor = getPixelColor(renderX, renderY);
          let topColor2 = getPixelColor(renderX + 1u, renderY);

          let blendedTop = blendColors(topColor, topColor2);

          let bottomColor = getPixelColor(renderX, renderY + 1u);
          let bottomColor2 = getPixelColor(renderX + 1u, renderY + 1u);
          let blendedBottom = blendColors(bottomColor, bottomColor2);

          pixelsRgba[0] = blendedTop;      // TL
          pixelsRgba[1] = blendedTop;      // TR
          pixelsRgba[2] = blendedBottom;   // BL
          pixelsRgba[3] = blendedBottom;   // BR
      } else {
          pixelsRgba[0] = getPixelColor(renderX, renderY);         // TL
          pixelsRgba[1] = getPixelColor(renderX + 1u, renderY);   // TR
          pixelsRgba[2] = getPixelColor(renderX, renderY + 1u);   // BL
          pixelsRgba[3] = getPixelColor(renderX + 1u, renderY + 1u); // BR
      }

      let cellResult = renderQuadrantBlock(pixelsRgba);

      let outputIndex = cellY * bufferWidthCells + cellX;
      output.cells[outputIndex] = cellResult;
  }
  |wgsl}
