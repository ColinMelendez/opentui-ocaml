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
  pipeline_unlit : Wgpu.render_pipeline;
  pipeline_lambert : Wgpu.render_pipeline;
  mutable meshes : mesh_entry list;
  uniforms : floatarray;
  view_model : Matrix4.t;
  mvp : Matrix4.t;
}

let usage_vertex =
  Int64.logor Wgpu.buffer_usage_vertex Wgpu.buffer_usage_copy_destination
let usage_index =
  Int64.logor Wgpu.buffer_usage_index Wgpu.buffer_usage_copy_destination

let usage_uniform =
  Int64.logor Wgpu.buffer_usage_uniform Wgpu.buffer_usage_copy_destination

let ( let* ) = Result.bind

let destroy_mesh_entry entry =
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
}

let no_lights =
  { ambient_r = 0.0;
    ambient_g = 0.0;
    ambient_b = 0.0;
    ambient_a = 0.0;
    light_dir = Vector3.create ~y:1.0 ();
    light_color = Color.create ~r:0.0 ~g:0.0 ~b:0.0 () }

let world_translation m =
  (Float.Array.get m 12, Float.Array.get m 13, Float.Array.get m 14)

let scan_lights root =
  let ambient = ref no_lights in
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
      | _ -> ());
      List.iter walk (Object3d.children node)
    end
  in
  walk root;
  match !directional with
  | None -> !ambient
  | Some node -> (
      match Object3d.kind node with
      | Object3d.Directional_light (state, target) ->
          let lx, ly, lz = world_translation (Object3d.matrix_world node) in
          let tx, ty, tz = world_translation (Object3d.matrix_world target) in
          let dir =
            Vector3.normalize
              (Vector3.create ~x:(lx -. tx) ~y:(ly -. ty) ~z:(lz -. tz) ())
          in
          { !ambient with
            light_dir = dir;
            light_color =
              Color.create
                ~r:(state.color.r *. state.intensity)
                ~g:(state.color.g *. state.intensity)
                ~b:(state.color.b *. state.intensity)
                () }
      | _ -> !ambient)

let distance_squared_to ax ay az node =
  let mx, my, mz = world_translation (Object3d.matrix_world node) in
  let dx = mx -. ax and dy = my -. ay and dz = mz -. az in
  (dx *. dx) +. (dy *. dy) +. (dz *. dz)

let pack_uniforms t ~projection ~camera_inverse node material lights =
  let model_world = Object3d.matrix_world node in
  Matrix4.multiply t.view_model camera_inverse model_world;
  Matrix4.multiply t.mvp projection t.view_model;
  let u = t.uniforms in
  Float.Array.blit t.mvp 0 u Shaders.slot_mvp 16;
  Float.Array.blit model_world 0 u Shaders.slot_model 16;
  Float.Array.set u Shaders.slot_color material.Material.color.r;
  Float.Array.set u (Shaders.slot_color + 1) material.Material.color.g;
  Float.Array.set u (Shaders.slot_color + 2) material.Material.color.b;
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
  Float.Array.set u (Shaders.slot_ambient + 3) lights.ambient_a

let create ~width ~height () =
  Wgpu.enable_diagnostics ();
  match Wgpu.create_device () with
  | Error _ as failure -> failure
  | Ok device -> (
      match Wgpu.create_render_target device ~width ~height with
      | Error _ as failure ->
          Wgpu.destroy_device device;
          failure
      | Ok target -> (
          let stride = Wgpu.readback_stride ~width in
          match Wgpu.create_readback device ~stride ~rows:height with
          | Error _ as failure ->
              Wgpu.destroy_render_target target;
              Wgpu.destroy_device device;
              failure
          | Ok readback -> (
              let close_through_readback () =
                Wgpu.destroy_readback readback;
                Wgpu.destroy_render_target target;
                Wgpu.destroy_device device
              in
              match Wgpu.create_shader_module device ~wgsl:Shaders.wgsl_unlit with
              | Error _ as failure -> close_through_readback (); failure
              | Ok shader_unlit -> (
                  let close_through_unlit () =
                    Wgpu.destroy_shader_module shader_unlit;
                    close_through_readback ()
                  in
                  match
                    Wgpu.create_shader_module device ~wgsl:Shaders.wgsl_lambert
                  with
                  | Error _ as failure -> close_through_unlit (); failure
                  | Ok shader_lambert -> (
                      let close_through_lamberts () =
                        Wgpu.destroy_shader_module shader_lambert;
                        close_through_unlit ()
                      in
                      match
                        Wgpu.create_uniform_bind_group_layout device
                      with
                      | Error _ as failure ->
                          close_through_lamberts (); failure
                      | Ok bgl -> (
                          let close_through_bgl () =
                            Wgpu.destroy_bind_group_layout bgl;
                            close_through_lamberts ()
                          in
                          match Wgpu.create_pipeline_layout device bgl with
                          | Error _ as failure ->
                              close_through_bgl (); failure
                          | Ok playout -> (
                              let close_through_playout () =
                                Wgpu.destroy_pipeline_layout playout;
                                close_through_bgl ()
                              in
                              match
                                Wgpu.create_render_pipeline device
                                  ~layout:playout ~shader:shader_unlit
                                  ~vs_entry:"vs_main" ~fs_entry:"fs_main"
                                  ~target_format:
                                    Wgpu.texture_format_rgba8_unorm
                              with
                              | Error _ as failure ->
                                  close_through_playout (); failure
                              | Ok pipeline_unlit -> (
                                  let close_through_unlit_pipeline () =
                                    Wgpu.destroy_render_pipeline
                                      pipeline_unlit;
                                    close_through_playout ()
                                  in
                                  match
                                    Wgpu.create_render_pipeline device
                                      ~layout:playout ~shader:shader_lambert
                                      ~vs_entry:"vs_main" ~fs_entry:"fs_main"
                                      ~target_format:
                                        Wgpu.texture_format_rgba8_unorm
                                  with
                                  | Error _ as failure ->
                                      close_through_unlit_pipeline ();
                                      failure
                                  | Ok pipeline_lambert ->
                                      Ok
                                        { device;
                                          target;
                                          readback;
                                          staging =
                                            Bigarray.Array1.create
                                              Bigarray.char Bigarray.c_layout
                                              (Wgpu.readback_size readback);
                                          width;
                                          height;
                                          bgl;
                                          playout;
                                          shader_unlit;
                                          shader_lambert;
                                          pipeline_unlit;
                                          pipeline_lambert;
                                          meshes = [];
                                          uniforms =
                                            Float.Array.make uniform_floats
                                              0.0;
                                          view_model = Matrix4.create ();
                                          mvp = Matrix4.create () }))))))))

let render t ~(root : Object3d.t) ~(camera : Object3d.t)
    ~(clear_color : float * float * float * float) () =
  (match Object3d.kind camera with
  | Object3d.Perspective_camera _ -> ()
  | _ ->
      raise
        (Invalid_argument "Engine.render: camera node is not a perspective camera"));
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
  let projection = Object3d.projection_matrix camera in
  let camera_inverse = Object3d.matrix_world_inverse camera in
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
            pack_uniforms t ~projection ~camera_inverse node material lights;
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
                      | Material.Lambert -> t.pipeline_lambert);
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
      | Ok () -> (
          match Wgpu.map_read t.device t.readback with
          | Error _ as failure -> failure
          | Ok () -> (
              match Wgpu.copy_mapped t.readback t.staging with
              | Error _ as failure -> failure
              | Ok () ->
                  Wgpu.unmap t.readback;
                  Ok ())))

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
            Wgpu.destroy_readback old_readback;
            Wgpu.destroy_render_target old_target;
            Ok ())

let width t = t.width

let height t = t.height

let destroy t =
  List.iter destroy_mesh_entry t.meshes;
  t.meshes <- [];
  Wgpu.destroy_render_pipeline t.pipeline_unlit;
  Wgpu.destroy_render_pipeline t.pipeline_lambert;
  Wgpu.destroy_shader_module t.shader_unlit;
  Wgpu.destroy_shader_module t.shader_lambert;
  Wgpu.destroy_pipeline_layout t.playout;
  Wgpu.destroy_bind_group_layout t.bgl;
  Wgpu.destroy_readback t.readback;
  Wgpu.destroy_render_target t.target;
  Wgpu.destroy_device t.device
