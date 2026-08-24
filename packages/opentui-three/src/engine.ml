(** Phase-1 rendering core: walks a scene graph, uploads mesh GPU state,
    packs uniforms, and drives the WebGPU frame through {!Opentui_wgpu}.
    The phase-2 CLI facade composes over this module; headless consumers can
    drive it directly. *)

module Wgpu = Opentui_wgpu.Wgpu

let uniform_floats = Shaders.uniform_floats

let uniform_bytes = uniform_floats * 4

type mesh_entry = {
  node : Object3d.t;
  geometry : Geometry.t;
  vertex_buffer : Wgpu.Native_token.Buffer.t;
  vertex_size : int;
  index_buffer : Wgpu.Native_token.Buffer.t;
  index_size : int;
  index_count : int;
  uniform_buffer : Wgpu.Native_token.Buffer.t;
  group : Wgpu.bind_group;
}

type super_sample = [ `None | `Cpu | `Gpu ]

type sample_algorithm = [ `Standard | `Pre_squeezed ]

type supersampler = {
  ss_shader : Wgpu.shader_module;
  ss_bgl : Wgpu.bind_group_layout;
  ss_playout : Wgpu.pipeline_layout;
  ss_pipeline : Wgpu.compute_pipeline;
  params : Wgpu.Native_token.Buffer.t;
  mutable storage : Wgpu.Native_token.Buffer.t;
  mutable readback : Wgpu.readback;
  mutable group : Wgpu.bind_group;
  mutable cells_x : int;
  mutable cells_y : int;
  mutable algorithm : sample_algorithm;
  mutable staging :
    (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t;
}

type t = {
  device : Wgpu.device;
  mutable target : Wgpu.render_target;
  mutable readback : Wgpu.readback;
  mutable staging :
    (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t;
  mutable width : int;
  mutable height : int;
  bgl : Wgpu.bind_group_layout;
  playout : Wgpu.pipeline_layout;
  shader_unlit : Wgpu.shader_module;
  shader_lambert : Wgpu.shader_module;
  shader_phong : Wgpu.shader_module;
  pipeline_unlit : Wgpu.render_pipeline;
  pipeline_lambert : Wgpu.render_pipeline;
  pipeline_phong : Wgpu.render_pipeline;
  mutable meshes : mesh_entry list;
  uniforms : floatarray;
  view_model : Matrix4.t;
  mvp : Matrix4.t;
  mutable super_sample : super_sample;
  mutable sample_algorithm : sample_algorithm;
  mutable supersampler : supersampler option;
}
let pack_u32_le values =
  let bytes = Bytes.create (List.length values * 4) in
  List.iteri
    (fun index value ->
      let open Int32 in
      let word = Int32.of_int value in
      Bytes.set_int32_le bytes (index * 4) word)
    values;
  Bytes.to_string bytes

let usage_vertex =
  Int64.logor Wgpu.buffer_usage_vertex Wgpu.buffer_usage_copy_destination
let usage_index =
  Int64.logor Wgpu.buffer_usage_index Wgpu.buffer_usage_copy_destination

let usage_uniform =
  Int64.logor Wgpu.buffer_usage_uniform Wgpu.buffer_usage_copy_destination

let ( let* ) = Result.bind

let destroy_mesh_entry (entry : mesh_entry) =
  Wgpu.destroy_bind_group entry.group;
  Wgpu.destroy_buffer entry.uniform_buffer;
  Wgpu.destroy_buffer entry.index_buffer;
  Wgpu.destroy_buffer entry.vertex_buffer

let create_mesh_entry device bgl node geometry =
  let vertex_bytes = Wgpu.pack_f32_le (Geometry.interleaved geometry) in
  let index_bytes = Wgpu.pack_indices_u16 (Geometry.indices geometry) in
  let* vertex_buffer =
    Wgpu.create_buffer device ~size:(String.length vertex_bytes)
      ~usage:usage_vertex
  in
  let close_vertex () = Wgpu.destroy_buffer vertex_buffer in
  let* index_buffer =
    match
      Wgpu.create_buffer device ~size:(Wgpu.align4 (String.length index_bytes))
        ~usage:usage_index
    with
    | Ok buffer -> Ok buffer
    | Error _ as failure ->
        close_vertex ();
        failure
  in
  let close_index () =
    Wgpu.destroy_buffer index_buffer;
    close_vertex ()
  in
  let* uniform_buffer =
    match Wgpu.create_buffer device ~size:uniform_bytes ~usage:usage_uniform with
    | Ok buffer -> Ok buffer
    | Error _ as failure ->
        close_index ();
        failure
  in
  let close_uniform () =
    Wgpu.destroy_buffer uniform_buffer;
    close_index ()
  in
  let* group =
    match
      Wgpu.create_uniform_bind_group device bgl uniform_buffer ~size:uniform_bytes
    with
    | Ok group -> Ok group
    | Error _ as failure ->
        close_uniform ();
        failure
  in
  let close_group () =
    Wgpu.destroy_bind_group group;
    close_uniform ()
  in
  let* () =
    match Wgpu.write_buffer_string device vertex_buffer ~offset:0 vertex_bytes with
    | Ok () -> Ok ()
    | Error _ as failure ->
        close_group ();
        failure
  in
  let* () =
    match Wgpu.write_buffer_string device index_buffer ~offset:0 index_bytes with
    | Ok () -> Ok ()
    | Error _ as failure ->
        close_group ();
        failure
  in
  Ok
    { node;
      geometry;
      vertex_buffer;
      vertex_size = String.length vertex_bytes;
      index_buffer;
      index_size = String.length index_bytes;
      index_count = Array.length (Geometry.indices geometry);
      uniform_buffer;
      group }

let mesh_geometry node =
  match Object3d.kind node with
  | Object3d.Mesh (geometry, _) -> geometry
  | _ -> raise (Invalid_argument "engine: non-mesh in draw list")

let entry_for t node =
  let geometry = mesh_geometry node in
  match List.find_opt (fun e -> e.node == node) t.meshes with
  | Some entry when entry.geometry == geometry -> Ok entry
  | Some entry ->
      (* The node swapped to a different geometry instance; the cached
         upload belongs to the old one and must not be reused. *)
      destroy_mesh_entry entry;
      t.meshes <- List.filter (fun e -> not (e == entry)) t.meshes;
      let* fresh = create_mesh_entry t.device t.bgl node geometry in
      t.meshes <- fresh :: t.meshes;
      Ok fresh
  | None ->
      let* entry = create_mesh_entry t.device t.bgl node geometry in
      t.meshes <- entry :: t.meshes;
      Ok entry

(* --- GPU supersampling state --- *)

let destroy_supersampler t =
  match t.supersampler with
  | None -> ()
  | Some ss ->
      Wgpu.destroy_bind_group ss.group;
      Wgpu.destroy_readback ss.readback;
      Wgpu.destroy_buffer ss.storage;
      Wgpu.destroy_buffer ss.params;
      Wgpu.destroy_pipeline_layout ss.ss_playout;
      Wgpu.destroy_bind_group_layout ss.ss_bgl;
      Wgpu.destroy_compute_pipeline ss.ss_pipeline;
      Wgpu.destroy_shader_module ss.ss_shader;
      t.supersampler <- None

let supersampler_bytes cells_x cells_y =
  cells_x * cells_y * Cell_conversion.record_size

let ensure_supersampler t =
  match t.super_sample with
  | `None | `Cpu -> Ok ()
  | `Gpu -> (
      let cells_x = (t.width + 1) / 2 and cells_y = (t.height + 1) / 2 in
      match t.supersampler with
      | Some ss
        when Int.equal ss.cells_x cells_x
             && Int.equal ss.cells_y cells_y
             &&
             (match (ss.algorithm, t.sample_algorithm) with
             | `Standard, `Standard
             | `Pre_squeezed, `Pre_squeezed ->
                 true
             | _ -> false) ->
          Ok ()
      | _ -> (
        destroy_supersampler t;
        let bytes = supersampler_bytes cells_x cells_y in
        let* ss_shader =
          Wgpu.create_shader_module t.device ~wgsl:Shaders.wgsl_supersampling
        in
        let close_shader () = Wgpu.destroy_shader_module ss_shader in
        let* bgl =
          match Wgpu.create_supersampling_bind_group_layout t.device with
          | Ok bgl -> Ok bgl
          | Error _ as failure ->
              close_shader ();
              failure
        in
        let close_bgl () =
          Wgpu.destroy_bind_group_layout bgl;
          close_shader ()
        in
        let* playout =
          match Wgpu.create_pipeline_layout t.device bgl with
          | Ok playout -> Ok playout
          | Error _ as failure ->
              close_bgl ();
              failure
        in
        let close_playout () =
          Wgpu.destroy_pipeline_layout playout;
          close_bgl ()
        in
        let* pipeline =
          match
            Wgpu.create_compute_pipeline t.device ~layout:playout
              ~shader:ss_shader ~entry_point:"main"
          with
          | Ok pipeline -> Ok pipeline
          | Error _ as failure ->
              close_playout ();
              failure
        in
        let close_pipeline () =
          Wgpu.destroy_compute_pipeline pipeline;
          close_playout ()
        in
        (* Four u32s - width, height, algorithm, struct padding - matching
           the shader's 16-byte SuperSamplingParams exactly. *)
        let algo =
          match t.sample_algorithm with `Standard -> 0 | `Pre_squeezed -> 1
        in
        let params_bytes = pack_u32_le [ t.width; t.height; algo; 0 ] in
        let* params =
          match
            Wgpu.create_buffer t.device
              ~size:(Wgpu.align4 (String.length params_bytes))
              ~usage:(Int64.logor Wgpu.buffer_usage_uniform
                        Wgpu.buffer_usage_copy_destination)
          with
          | Ok buffer -> Ok buffer
          | Error _ as failure ->
              close_pipeline ();
              failure
        in
        let close_params () =
          Wgpu.destroy_buffer params;
          close_pipeline ()
        in
        let* () =
          match
            Wgpu.write_buffer_string t.device params ~offset:0 params_bytes
          with
          | Ok () -> Ok ()
          | Error _ as failure ->
              close_params ();
              failure
        in
        let* storage =
          match
            Wgpu.create_buffer t.device ~size:bytes
              ~usage:(Int64.logor Wgpu.buffer_usage_storage
                        Wgpu.buffer_usage_copy_source)
          with
          | Ok buffer -> Ok buffer
          | Error _ as failure ->
              close_params ();
              failure
        in
        let close_storage () =
          Wgpu.destroy_buffer storage;
          close_params ()
        in
        let* readback =
          match Wgpu.create_copy_readback t.device ~size:bytes with
          | Ok readback -> Ok readback
          | Error _ as failure ->
              close_storage ();
              failure
        in
        let close_readback () =
          Wgpu.destroy_readback readback;
          close_storage ()
        in
        let view = Wgpu.render_target_view t.target in
        let* group =
          match
            Wgpu.create_compute_bind_group t.device ~layout:bgl ~view ~storage
              ~storage_size:bytes ~params
          with
          | Ok group -> Ok group
          | Error _ as failure ->
              close_readback ();
              failure
        in
        t.supersampler <-
          Some
            { ss_shader;
              ss_bgl = bgl;
              ss_playout = playout;
              ss_pipeline = pipeline;
              params;
              storage;
              readback;
              group;
              cells_x;
              cells_y;
              algorithm = t.sample_algorithm;
              staging =
                Bigarray.Array1.create Bigarray.char Bigarray.c_layout bytes };
        Ok ()))

let set_super_sample t mode =
  t.super_sample <- mode;
  match mode with
  | `Gpu -> ensure_supersampler t
  | `None | `Cpu ->
      destroy_supersampler t;
      Ok ()

let set_super_sample_algorithm t algorithm =
  t.sample_algorithm <- algorithm;
  match t.super_sample with
  | `Gpu -> ensure_supersampler t
  | `None | `Cpu -> Ok ()

let last_cell_grid t =
  match t.supersampler with
  | Some ss -> (ss.cells_x, ss.cells_y)
  | None -> (0, 0)

let last_cells t =
  match t.supersampler with
  | None -> ""
  | Some ss ->
      let bytes = supersampler_bytes ss.cells_x ss.cells_y in
      let out = Bytes.create bytes in
      for i = 0 to bytes - 1 do
        Bytes.set out i (Bigarray.Array1.get ss.staging i)
      done;
      Bytes.to_string out

(* Visible-scene scans share one pruning rule: an invisible node hides its
   whole subtree from rendering and lighting, while matrix updates still run
   for the untouched parts of the graph above it. *)

let collect_visible node =
  let rec walk acc node =
    if Object3d.visible node then begin
      let acc =
        match Object3d.kind node with
        | Object3d.Mesh _ -> node :: acc
        | _ -> acc
      in
      List.fold_left walk acc (Object3d.children node)
    end
    else acc
  in
  List.rev (walk [] node)

type lights = {
  ambient_r : float;
  ambient_g : float;
  ambient_b : float;
  ambient_a : float;
  light_dir : Vector3.t;
  light_color : Color.t;
  points :
    (float * float * float * float * float * float * float) list;
        (* x, y, z, cutoff, r, g, b - already scaled by intensity, in scene
           order, at most {!Shaders.max_point_lights} entries *)
}

let no_lights =
  { ambient_r = 0.0;
    ambient_g = 0.0;
    ambient_b = 0.0;
    ambient_a = 0.0;
    light_dir = Vector3.create ~y:1.0 ();
    light_color = Color.create ~r:0.0 ~g:0.0 ~b:0.0 ();
    points = [] }

let world_translation m =
  (Float.Array.get m 12, Float.Array.get m 13, Float.Array.get m 14)

let scan_lights root =
  let ambient = ref no_lights in
  let points = ref [] in
  let directional : Object3d.t option ref = ref None in
  let rec walk node =
    if Object3d.visible node then begin
      (match Object3d.kind node with
      | Object3d.Ambient_light state ->
          (* Color carries its own channels; intensity rides in the alpha
             slot exactly once - the shader applies ambient.rgb *
             ambient.a. *)
          let a = !ambient in
          ambient :=
            { a with
              ambient_r = a.ambient_r +. state.color.r;
              ambient_g = a.ambient_g +. state.color.g;
              ambient_b = a.ambient_b +. state.color.b;
              ambient_a = a.ambient_a +. state.intensity }
      | Object3d.Directional_light _ when Option.is_none !directional ->
          directional := Some node
      | Object3d.Point_light state
        when List.length !points < Shaders.max_point_lights ->
          let px, py, pz = world_translation (Object3d.matrix_world node) in
          points :=
            ( px,
              py,
              pz,
              state.distance,
              state.color.r *. state.intensity,
              state.color.g *. state.intensity,
              state.color.b *. state.intensity )
            :: !points
      | _ -> ());
      List.iter walk (Object3d.children node)
    end
  in
  walk root;
  let result = { !ambient with points = List.rev !points } in
  match !directional with
  | None -> result
  | Some node -> (
      match Object3d.kind node with
      | Object3d.Directional_light (state, target) ->
          let lx, ly, lz = world_translation (Object3d.matrix_world node) in
          let tx, ty, tz = world_translation (Object3d.matrix_world target) in
          let dir =
            Vector3.normalize
              (Vector3.create ~x:(lx -. tx) ~y:(ly -. ty) ~z:(lz -. tz) ())
          in
          { result with
            light_dir = dir;
            light_color =
              Color.create
                ~r:(state.color.r *. state.intensity)
                ~g:(state.color.g *. state.intensity)
                ~b:(state.color.b *. state.intensity)
                () }
      | _ -> result)

let distance_squared_to ax ay az node =
  let mx, my, mz = world_translation (Object3d.matrix_world node) in
  let dx = mx -. ax and dy = my -. ay and dz = mz -. az in
  (dx *. dx) +. (dy *. dy) +. (dz *. dz)

let pack_uniforms t ~(camera : Object3d.t) node material lights =
  let projection = Object3d.projection_matrix camera in
  let camera_inverse = Object3d.matrix_world_inverse camera in
  let model_world = Object3d.matrix_world node in
  Matrix4.multiply t.view_model camera_inverse model_world;
  Matrix4.multiply t.mvp projection t.view_model;
  let u = t.uniforms in
  Float.Array.blit t.mvp 0 u Shaders.slot_mvp 16;
  Float.Array.blit model_world 0 u Shaders.slot_model 16;
  let albedo = Material.color material in
  Float.Array.set u Shaders.slot_color albedo.r;
  Float.Array.set u (Shaders.slot_color + 1) albedo.g;
  Float.Array.set u (Shaders.slot_color + 2) albedo.b;
  Float.Array.set u (Shaders.slot_color + 3) 1.0;
  Float.Array.set u Shaders.slot_light_dir lights.light_dir.x;
  Float.Array.set u (Shaders.slot_light_dir + 1) lights.light_dir.y;
  Float.Array.set u (Shaders.slot_light_dir + 2) lights.light_dir.z;
  Float.Array.set u (Shaders.slot_light_dir + 3) 0.0;
  Float.Array.set u Shaders.slot_light_color lights.light_color.r;
  Float.Array.set u (Shaders.slot_light_color + 1) lights.light_color.g;
  Float.Array.set u (Shaders.slot_light_color + 2) lights.light_color.b;
  Float.Array.set u (Shaders.slot_light_color + 3) 0.0;
  Float.Array.set u Shaders.slot_ambient lights.ambient_r;
  Float.Array.set u (Shaders.slot_ambient + 1) lights.ambient_g;
  Float.Array.set u (Shaders.slot_ambient + 2) lights.ambient_b;
  Float.Array.set u (Shaders.slot_ambient + 3) lights.ambient_a;
  let spec = Material.specular material in
  Float.Array.set u Shaders.slot_specular_shininess spec.r;
  Float.Array.set u (Shaders.slot_specular_shininess + 1) spec.g;
  Float.Array.set u (Shaders.slot_specular_shininess + 2) spec.b;
  Float.Array.set u (Shaders.slot_specular_shininess + 3)
    (Material.shininess material);
  let emissive = Material.emissive material in
  Float.Array.set u Shaders.slot_emissive_intensity emissive.r;
  Float.Array.set u (Shaders.slot_emissive_intensity + 1) emissive.g;
  Float.Array.set u (Shaders.slot_emissive_intensity + 2) emissive.b;
  Float.Array.set u (Shaders.slot_emissive_intensity + 3)
    (Material.emissive_intensity material);
  for slot = 0 to Shaders.max_point_lights - 1 do
    let base = Shaders.slot_point_positions + (slot * 4) in
    if slot < List.length lights.points then begin
      let px, py, pz, cutoff, r, g, b =
        List.nth lights.points slot
      in
      Float.Array.set u base px;
      Float.Array.set u (base + 1) py;
      Float.Array.set u (base + 2) pz;
      Float.Array.set u (base + 3) cutoff;
      let color_base = Shaders.slot_point_colors + (slot * 4) in
      Float.Array.set u color_base r;
      Float.Array.set u (color_base + 1) g;
      Float.Array.set u (color_base + 2) b;
      Float.Array.set u (color_base + 3) 0.0
    end
    else begin
      Float.Array.fill u base 4 0.0;
      Float.Array.fill u (Shaders.slot_point_colors + (slot * 4)) 4 0.0
    end
  done;
  let cx, cy, cz = world_translation (Object3d.matrix_world camera) in
  Float.Array.set u Shaders.slot_camera_position cx;
  Float.Array.set u (Shaders.slot_camera_position + 1) cy;
  Float.Array.set u (Shaders.slot_camera_position + 2) cz;
  Float.Array.set u (Shaders.slot_camera_position + 3) 1.0

let create ~width ~height () =
  Wgpu.enable_diagnostics ();
  let releases = ref [] in
  let own release = releases := release :: !releases in
  let fail error =
    List.iter (fun release -> release ()) !releases;
    Error error
  in
  match Wgpu.create_device () with
  | Error _ as failure -> failure
  | Ok device -> (
      own (fun () -> Wgpu.destroy_device device);
      match Wgpu.create_render_target device ~width ~height with
      | Error error -> fail error
      | Ok target -> (
          own (fun () -> Wgpu.destroy_render_target target);
          match
            Wgpu.create_readback device
              ~stride:(Wgpu.readback_stride ~width)
              ~rows:height
          with
          | Error error -> fail error
          | Ok readback -> (
              own (fun () -> Wgpu.destroy_readback readback);
              let staging =
                Bigarray.Array1.create Bigarray.char Bigarray.c_layout
                  (Wgpu.readback_size readback)
              in
              let build_shader wgsl what =
                match Wgpu.create_shader_module device ~wgsl with
                | Ok module_ ->
                    own (fun () -> Wgpu.destroy_shader_module module_);
                    Ok module_
                | Error error ->
                    ignore what;
                    fail error
              in
              match build_shader Shaders.wgsl_unlit "unlit" with
              | Error error -> fail error
              | Ok shader_unlit -> (
                  match build_shader Shaders.wgsl_lambert "lambert" with
                      | Error error -> fail error
                      | Ok shader_lambert -> (
                          match build_shader Shaders.wgsl_phong "phong" with
                          | Error error -> fail error
                          | Ok shader_phong -> (
                              match
                                Wgpu.create_uniform_bind_group_layout device
                              with
                              | Error error -> fail error
                              | Ok bgl -> (
                                  own (fun () ->
                                    Wgpu.destroy_bind_group_layout bgl);
                                  match Wgpu.create_pipeline_layout device bgl with
                                  | Error error -> fail error
                                  | Ok playout -> (
                                      own (fun () ->
                                        Wgpu.destroy_pipeline_layout playout);
                                      let make_pipeline shader =
                                        Wgpu.create_render_pipeline device
                                          ~layout:playout ~shader
                                          ~vs_entry:"vs_main"
                                          ~fs_entry:"fs_main"
                                          ~target_format:
                                            Wgpu.texture_format_rgba8_unorm
                                      in
                                      match make_pipeline shader_unlit with
                                      | Error error -> fail error
                                      | Ok pipeline_unlit -> (
                                          own (fun () ->
                                            Wgpu.destroy_render_pipeline
                                              pipeline_unlit);
                                          match make_pipeline shader_lambert with
                                          | Error error -> fail error
                                          | Ok pipeline_lambert -> (
                                              own (fun () ->
                                                Wgpu.destroy_render_pipeline
                                                  pipeline_lambert);
                                              match make_pipeline shader_phong with
                                              | Error error -> fail error
                                              | Ok pipeline_phong -> (
                                                  own (fun () ->
                                                    Wgpu.destroy_render_pipeline
                                                      pipeline_phong);
                                                  Ok
                                                    { device;
                                                      target;
                                                      readback;
                                                      staging;
                                                      width;
                                                      height;
                                                      bgl;
                                                      playout;
                                                      shader_unlit;
                                                      shader_lambert;
                                                      shader_phong;
                                                      pipeline_unlit;
                                                      pipeline_lambert;
                                                      pipeline_phong;
                                                      meshes = [];
                                                      uniforms =
                                                        Float.Array.make
                                                          uniform_floats 0.0;
                                                      view_model =
                                                        Matrix4.create ();
                                                      mvp = Matrix4.create ();
                                                      supersampler = None;
                                                      super_sample = `None;
                                                      sample_algorithm =
                                                        `Standard;
                                                  })))))))))))

let submit t ~(root : Object3d.t) ~(camera : Object3d.t)
    ~(clear_color : float * float * float * float) () =
  (* Scene walk, uniform upload, draw encoding, and queue submission.
     Completion is observed by {!stage}. *)
  (match Object3d.kind camera with
  | Object3d.Perspective_camera _ -> ()
  | _ ->
      raise
        (Invalid_argument "Engine.submit: camera node is not a perspective camera"));
  Object3d.update_matrix_world root;
  Perspective_camera.update_matrices camera;
  let meshes = collect_visible root in
  let cx, cy, cz = world_translation (Object3d.matrix_world camera) in
  let ordered =
    List.stable_sort
      (fun a b ->
        Float.compare
          (distance_squared_to cx cy cz a)
          (distance_squared_to cx cy cz b))
      meshes
  in
  let lights = scan_lights root in
  let rec gather acc = function
    | [] -> Ok (List.rev acc)
    | node :: rest -> (
        match entry_for t node with
        | Error _ as failure -> failure
        | Ok entry ->
            let material =
              match Object3d.kind node with
              | Object3d.Mesh (_, material) -> material
              | _ -> raise (Invalid_argument "engine: non-mesh in draw list")
            in
            pack_uniforms t ~camera node material lights;
            match
              Wgpu.write_buffer_string t.device entry.uniform_buffer ~offset:0
                (Wgpu.pack_f32_le t.uniforms)
            with
            | Error _ as failure -> failure
            | Ok () ->
                let draw =
                  { Wgpu.pipeline =
                      (match Material.kind material with
                      | Material.Basic -> t.pipeline_unlit
                      | Material.Lambert -> t.pipeline_lambert
                      | Material.Phong -> t.pipeline_phong);
                    group = entry.group;
                    vertex_buffer = entry.vertex_buffer;
                    vertex_size = entry.vertex_size;
                    index_buffer = entry.index_buffer;
                    index_size = entry.index_size;
                    index_count = entry.index_count }
                in
                gather (draw :: acc) rest)
  in
  match gather [] ordered with
  | Error _ as failure -> failure
  | Ok draws -> (
      match
        Wgpu.submit_draw_frame t.device ~target:t.target ~readback:t.readback
          ~clear:clear_color ~draws ()
      with
      | Error _ as failure -> failure
      | Ok () ->
          (* The staging area now belongs to the in-flight frame; the caller
             observes completion through {!Engine.stage}. *)
          Ok ())

let stage t =
  (* Block until the submitted frame's output lands in owned staging: the
     pixel readback for None/Cpu modes, or compute-pass cell records for
     Gpu. One readback path per mode, awaited immediately - reference
     parity. *)
  match t.super_sample with
  | `Gpu -> (
      match t.supersampler with
      | None ->
          Error
            (Wgpu.Error.Invalid_argument
               "gpu super sampling requested without compute state")
      | Some ss -> (
          let groups_x = (ss.cells_x + 3) / 4 and groups_y = (ss.cells_y + 3) / 4 in
          match
            Wgpu.dispatch_compute_pass t.device ~pipeline:ss.ss_pipeline
              ~group:ss.group ~groups_x ~groups_y ~source:ss.storage
              ~destination:ss.readback
          with
          | Error _ as failure -> failure
          | Ok () -> (
              match Wgpu.map_read t.device ss.readback with
              | Error _ as failure -> failure
              | Ok () -> (
                  match Wgpu.copy_mapped ss.readback ss.staging with
                  | Error _ as failure -> failure
                  | Ok () ->
                      Wgpu.unmap ss.readback;
                      Ok ()))))
  | `None | `Cpu -> (
      match Wgpu.map_read t.device t.readback with
      | Error _ as failure -> failure
      | Ok () -> (
          match Wgpu.copy_mapped t.readback t.staging with
          | Error _ as failure -> failure
          | Ok () ->
              Wgpu.unmap t.readback;
              Ok ()))

let render t ~(root : Object3d.t) ~(camera : Object3d.t)
    ~(clear_color : float * float * float * float) () =
  let* () = submit t ~root ~camera ~clear_color () in
  stage t

let snapshot t =
  (* Strips the 256-byte row padding from the staged frame; only valid after
     a successful {!render}. *)
  let stride = Wgpu.readback_stride ~width:t.width in
  let row_bytes = t.width * 4 in
  let bytes = Bytes.create (row_bytes * t.height) in
  for row = 0 to t.height - 1 do
    for column = 0 to row_bytes - 1 do
      Bytes.set bytes ((row * row_bytes) + column)
        (Bigarray.Array1.get t.staging ((row * stride) + column))
    done
  done;
  Bytes.to_string bytes

let upload_frame t ~(data : string) ~(bytes_per_row : int) =
  (* Queue-writes caller bytes straight into the current frame texture;
     the primary consumer is the oracle test feeding known pixels through
     the GPU supersampling pass. *)
  Wgpu.write_texture_bytes t.device
    ~texture:(Wgpu.render_target_texture t.target)
    ~data ~bytes_per_row ~width:t.width ~height:t.height

let resize t ~width ~height =
  if width <= 0 || height <= 0 then
    Error
      (Wgpu.Error.Invalid_argument "engine size must be positive")
  else
    match Wgpu.create_render_target t.device ~width ~height with
    | Error _ as failure -> failure
    | Ok target -> (
        match
          Wgpu.create_readback t.device
            ~stride:(Wgpu.readback_stride ~width)
            ~rows:height
        with
        | Error _ as failure ->
            Wgpu.destroy_render_target target;
            failure
        | Ok readback ->
            let old_target = t.target and old_readback = t.readback in
            t.target <- target;
            t.readback <- readback;
            t.width <- width;
            t.height <- height;
            t.staging <-
              Bigarray.Array1.create Bigarray.char Bigarray.c_layout
                (Wgpu.readback_size readback);
            let* () =
              match t.super_sample with
              | `Gpu -> ensure_supersampler t
              | `None | `Cpu -> Ok ()
            in
            Wgpu.destroy_readback old_readback;
            Wgpu.destroy_render_target old_target;
            Ok ())

let width t = t.width

let height t = t.height

let destroy t =
  destroy_supersampler t;
  List.iter destroy_mesh_entry t.meshes;
  t.meshes <- [];
  Wgpu.destroy_render_pipeline t.pipeline_unlit;
  Wgpu.destroy_render_pipeline t.pipeline_lambert;
  Wgpu.destroy_render_pipeline t.pipeline_phong;
  Wgpu.destroy_shader_module t.shader_unlit;
  Wgpu.destroy_shader_module t.shader_lambert;
  Wgpu.destroy_shader_module t.shader_phong;
  Wgpu.destroy_pipeline_layout t.playout;
  Wgpu.destroy_bind_group_layout t.bgl;
  Wgpu.destroy_readback t.readback;
  Wgpu.destroy_render_target t.target;
  Wgpu.destroy_device t.device
