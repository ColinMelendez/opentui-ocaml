(** The CLI facade, port of the reference ThreeCliRenderer (WGPURenderer.ts):
    options, default camera, cell aspect ratio, resize wiring semantics,
    draw_scene into an owned buffer through cell conversion, super-sample
    toggling, stats overlay, and teardown. *)

module Wgpu = Opentui_wgpu.Wgpu

module Core_color = Opentui_core.Color

module Core_error = Opentui_core.Error

module Error = struct
  type t =
    | Gpu of Wgpu.Error.t
    | Buffer of Core_error.t
    | Invalid_argument of string
    | Concurrent_draw_scene

  let message = function
    | Gpu error -> "gpu: " ^ Wgpu.Error.message error
    | Buffer error -> "buffer: " ^ Core_error.message error
    | Invalid_argument detail -> "invalid argument: " ^ detail
    | Concurrent_draw_scene ->
        "draw_scene was called concurrently, which is not supported"
end

type super_sample = [ `None | `Cpu | `Gpu ]

let default_super_sample : super_sample = `Gpu

(* The reference reads CELL_ASPECT_RATIO once at construction; an
   unparseable value falls back to the terminal-derived default. *)
let env_aspect_ratio () =
  match Sys.getenv_opt "CELL_ASPECT_RATIO" with
  | Some raw -> Float.of_string_opt raw
  | None -> None

type t = {
  mutable output_width : int;
  mutable output_height : int;
  mutable super_sample : super_sample;
  mutable background : float * float * float * float;
  alpha : bool;
  cell_aspect_ratio : float option;
  mutable camera : Object3d.t;
  mutable engine : Engine.t option;
  mutable rendering : bool;
  mutable destroyed : bool;
  mutable stats_enabled : bool;
  mutable render_ms : float;
  mutable readback_ms : float;
  mutable total_ms : float;
}

let render_dimensions t =
  match t.super_sample with
  | `None -> (t.output_width, t.output_height)
  | `Cpu | `Gpu -> (t.output_width * 2, t.output_height * 2)

let aspect_ratio t =
  match t.cell_aspect_ratio with
  | Some explicit -> explicit
  | None ->
      Float.of_int t.output_width /. (Float.of_int t.output_height *. 2.0)

let create ?focal_length ?(background_color = Core_color.black)
    ?(super_sample = default_super_sample) ?(alpha = false) ?cell_aspect_ratio
    ~width ~height () =
  if width <= 0 || height <= 0 then
    Error (Error.Invalid_argument "renderer dimensions must be positive")
  else
    let channel v = Float.of_int v /. 255.0 in
    let red, green, blue, bg_alpha = Core_color.channels background_color in
    (* Reference setBackgroundColor: background alpha passes through only
       when the renderer was built with alpha enabled. *)
    let clear_alpha = if alpha then channel bg_alpha else 1.0 in
    let background = (channel red, channel green, channel blue, clear_alpha) in
    let aspect =
      match cell_aspect_ratio with
      | Some explicit -> explicit
      | None -> (
          match env_aspect_ratio () with
          | Some env_value -> env_value
          | None -> Float.of_int width /. (Float.of_int height *. 2.0))
    in
    let fov_degrees =
      match focal_length with
      | Some focal ->
          (2.0 *. Float.atan (Float.of_int height /. (2.0 *. focal)))
          *. (180.0 /. Float.pi)
      | None -> 1.0
    in
    let camera =
      Perspective_camera.create ~fov_degrees ~aspect ~near:0.1 ~far:1000.0 ()
    in
    Vector3.set (Object3d.position camera) 0.0 0.0 3.0;
    Object3d.look_at ~target:(Vector3.create ()) camera;
    Perspective_camera.update_matrices camera;
    Ok
      { output_width = width;
        output_height = height;
        super_sample;
        background;
        alpha;
        cell_aspect_ratio;
        camera;
        engine = None;
        rendering = false;
        destroyed = false;
        stats_enabled = false;
        render_ms = 0.0;
        readback_ms = 0.0;
        total_ms = 0.0 }

let init t =
  if t.destroyed then Error (Error.Invalid_argument "renderer was destroyed")
  else if Option.is_some t.engine then
    Error (Error.Invalid_argument "renderer was already initialized")
  else
    let render_width, render_height = render_dimensions t in
    match Engine.create ~width:render_width ~height:render_height () with
    | Ok engine ->
        t.engine <- Some engine;
        Ok ()
    | Error error -> Error (Error.Gpu error)

let now_ms () = Unix.gettimeofday () *. 1000.0

let ( let* ) = Result.bind

(* Reference renderStats draws at a fixed offset over the framebuffer with
   soft gray text. The MapAsync/SS-Draw splits and algorithm line arrive
   with the phase-2 compute pass; this overlay reports the phase-1 phases. *)
let render_stats t ~(buffer : Opentui_core.Owned_buffer.t) =
  let fg =
    match Core_color.rgba ~red:229 ~green:229 ~blue:229 ~alpha:255 with
    | Ok color -> color
    | Error _ -> Core_color.white
  in
  let bg =
    match Core_color.rgba ~red:25 ~green:25 ~blue:25 ~alpha:255 with
    | Ok color -> color
    | Error _ -> Core_color.black
  in
  let mode =
    match t.super_sample with
    | `None -> "none"
    | `Cpu -> "cpu"
    | `Gpu -> "gpu"
  in
  let lines =
    [| "WebGPU Renderer Stats:";
       Printf.sprintf " Render: %.2fms" t.render_ms;
       Printf.sprintf " Readback: %.2fms" t.readback_ms;
       Printf.sprintf " Total Draw: %.2fms" t.total_ms;
       Printf.sprintf " SuperSample: %s" mode |]
  in
  Array.iteri
    (fun index line ->
      ignore
        (Opentui_core.Owned_buffer.draw_text buffer ~text:line ~x:3
           ~y:(4 + index) ~foreground:fg ~background:bg ~attributes:0l))
    lines

let draw_scene t ~(root : Object3d.t) ~(buffer : Opentui_core.Owned_buffer.t)
    ~(delta_time : float) : (unit, Error.t) result =
  ignore delta_time;
  if t.destroyed || Option.is_none t.engine then Ok ()
  else if t.rendering then Error Error.Concurrent_draw_scene
  else begin
    t.rendering <- true;
    let result =
      Fun.protect
        (fun () ->
          let engine = Option.get t.engine in
          let total_start = now_ms () in
          let result =
            match
              Engine.submit engine ~root ~camera:t.camera
                ~clear_color:t.background ()
            with
            | Error gpu -> Error (Error.Gpu gpu)
            | Ok () -> (
                let render_end = now_ms () in
                match Engine.stage engine with
                | Error gpu -> Error (Error.Gpu gpu)
                | Ok () -> (
                    let stage_end = now_ms () in
                    let snapshot = Engine.snapshot engine in
                    let conversion =
                      match t.super_sample with
                      | `None ->
                          Cell_conversion.write_none ~buffer ~snapshot
                            ~width:t.output_width ~height:t.output_height
                      | `Cpu | `Gpu ->
                          Cell_conversion.write_quadrants ~buffer ~snapshot
                            ~output_width:t.output_width
                            ~output_height:t.output_height
                    in
                    let write_end = now_ms () in
                    t.render_ms <- render_end -. total_start;
                    t.readback_ms <- write_end -. stage_end;
                    Result.map_error (fun e -> Error.Buffer e) conversion))
          in
          t.total_ms <- now_ms () -. total_start;
          result)
        ~finally:(fun () -> t.rendering <- false)
    in
    if t.stats_enabled then render_stats t ~buffer |> ignore;
    result
  end

let set_active_camera t camera =
  match Object3d.kind camera with
  | Object3d.Perspective_camera _ -> t.camera <- camera
  | _ ->
      (* Orthographic cameras arrive with phase 3; anything else is a
         programmer error at this boundary. *)
      invalid_arg "set_active_camera: node is not a perspective camera"

let active_camera t = t.camera

let set_background_color (color : Core_color.t) t =
  let channel v = Float.of_int v /. 255.0 in
  let red, green, blue, bg_alpha = Core_color.channels color in
  let clear_alpha = if t.alpha then channel bg_alpha else 1.0 in
  t.background <- (channel red, channel green, channel blue, clear_alpha)

(* Mirrors reference setSize: no-op unless dimensions changed or forced.
   The camera's aspect follows the output grid, not the render grid. *)
let set_size ?(force = false) t ~width ~height =
  if force || t.output_width <> width || t.output_height <> height then begin
    t.output_width <- width;
    t.output_height <- height;
    let render_width, render_height = render_dimensions t in
    let refresh_aspect () =
      let s =
        match Object3d.kind t.camera with
        | Object3d.Perspective_camera state -> state
        | _ -> invalid_arg "set_size: camera node is not a perspective camera"
      in
      s.aspect <- aspect_ratio t;
      Perspective_camera.update_projection_matrix t.camera
    in
    match t.engine with
    | Some engine -> (
        match Engine.resize engine ~width:render_width ~height:render_height with
        | Error gpu -> Error (Error.Gpu gpu)
        | Ok () ->
            refresh_aspect ();
            Ok ())
    | None ->
        refresh_aspect ();
        Ok ()
  end
  else Ok ()

let toggle_super_sampling t =
  t.super_sample <-
    (match t.super_sample with
    | `None -> `Cpu
    | `Cpu -> `Gpu
    | `Gpu -> `None);
  set_size ~force:true t ~width:t.output_width ~height:t.output_height

let toggle_debug_stats t = t.stats_enabled <- not t.stats_enabled

let get_super_sample t = t.super_sample

let destroy t =
  if not t.destroyed then begin
    t.destroyed <- true;
    Option.iter Engine.destroy t.engine;
    t.engine <- None
  end
