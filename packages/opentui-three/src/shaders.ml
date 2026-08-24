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

(* Verbatim port of vendor/opentui/packages/three/src/shaders/
   supersampling.wgsl with WORKGROUP_SIZE substituted. This is the twin of
   Cell_conversion's CPU oracle; the acceptance test requires bit-equal
   cells between them. *)
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
