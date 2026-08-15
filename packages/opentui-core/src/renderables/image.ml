module Image = Native_image

type fit = Fit | Cover | Fill

type source = Native of Image.t | Source of Image.source

type t = {
  renderable : Renderable.t;
  mutable source : source option;
  mutable image : Image.t option;
  mutable fit : fit;
  mutable protocol : Image.protocol;
  mutable load_error : Image.error option;
  on_load : (Image.t -> unit) option;
  on_error : (Image.error -> unit) option;
  buffered : bool;
  frame_buffer : Owned_buffer.t option;
  mutable destroyed : bool;
}

let as_renderable image = image.renderable
let image image = image.image
let source image = image.source
let fit image = image.fit
let protocol image = image.protocol
let load_error image = image.load_error
let loading _image = false
let buffered image = image.buffered

let ensure_alive image =
  if image.destroyed || Renderable.is_destroyed image.renderable then
    Error Error.Destroyed
  else Ok ()

let image_error_to_core = function
  | Image.Closed -> Error.Closed
  | Image.Invalid_argument -> Error.Invalid_argument
  | Image.Source_read | Image.Native _ -> Error.Unsupported

let capabilities context =
  match Render_context.capabilities context with
  | Ok value -> value
  | Error _ -> None

let has_pixel_resolution context =
  match
    ( Render_context.pixel_resolution context,
      Render_context.width context,
      Render_context.height context )
  with
  | Ok (Some value), Ok terminal_width, Ok terminal_height ->
      Int32.compare value.width 0l > 0 && Int32.compare value.height 0l > 0
      && Int32.compare terminal_width 0l > 0
      && Int32.compare terminal_height 0l > 0
  | _ -> false

let resolve_protocol requested capabilities ~has_resolution =
  let image_protocol_of_capability = function
    | Terminal_capabilities.Auto -> Image.Auto
    | Terminal_capabilities.Kitty -> Image.Kitty
    | Terminal_capabilities.Sixel -> Image.Sixel
    | Terminal_capabilities.Blocks -> Image.Blocks
  in
  let sixel_without_resolution = function
    | Image.Sixel when not has_resolution -> Image.Blocks
    | value -> value
  in
  match requested with
  | Image.Auto ->
      (match capabilities with
      | None -> Image.Blocks
      | Some capabilities ->
          let is_tmux =
            match capabilities.Terminal_capabilities.multiplexer with
            | Terminal_capabilities.Tmux -> true
            | No_multiplexer | Zellij | Screen | Unknown_multiplexer -> false
          in
          (match
             (image_protocol_of_capability
                capabilities.Terminal_capabilities.image_protocol)
           with
          | Image.Auto when is_tmux -> Image.Blocks
          | Image.Auto when capabilities.Terminal_capabilities.kitty_graphics ->
              Image.Kitty
          | Image.Auto when capabilities.Terminal_capabilities.sixel && has_resolution ->
              Image.Sixel
          | Image.Auto -> Image.Blocks
          | value -> value))
  | value -> sixel_without_resolution value

let context_cell_aspect_ratio context =
  match Render_context.pixel_resolution context with
  | Ok (Some resolution) ->
      (match Render_context.width context, Render_context.height context with
      | Ok terminal_width, Ok terminal_height
        when Int32.compare terminal_width 0l > 0
             && Int32.compare terminal_height 0l > 0 ->
          let cell_width =
            Int32.to_float resolution.width /. Int32.to_float terminal_width
          in
          let cell_height =
            Int32.to_float resolution.height /. Int32.to_float terminal_height
          in
          if Float.compare cell_width 0.0 > 0
             && Float.compare cell_height 0.0 > 0
          then cell_height /. cell_width
          else 2.0
      | _ -> 2.0)
  | Ok None | Error _ -> 2.0

let fitted_size image ~target_width ~target_height ?(cell_aspect = 2.0) () =
  match image.image with
  | None -> 0, 0
  | Some value ->
      (match Image.get_info value with
      | Error _ -> 0, 0
      | Ok info when info.width <= 0 || info.height <= 0 -> 0, 0
      | Ok info when target_width <= 0 || target_height <= 0 -> 0, 0
      | Ok _ when (match image.fit with Fill -> true | Fit | Cover -> false) ->
          target_width, target_height
      | Ok info ->
          let display_aspect =
            float_of_int info.width /. float_of_int info.height *. cell_aspect
          in
          let scale_width = float_of_int target_width /. display_aspect in
          let scale_height = float_of_int target_height in
          let scale =
            match image.fit with
            | Fit -> Float.min scale_width scale_height
            | Cover -> Float.max scale_width scale_height
            | Fill -> scale_height
          in
          ( max 1 (int_of_float (Float.round (display_aspect *. scale))),
            max 1 (int_of_float (Float.round scale)) ))

let source_dimensions image =
  match image.image with
  | None -> None
  | Some value ->
      (match Image.get_info value with
      | Ok info -> Some (info.width, info.height)
      | Error _ -> None)

let maybe_set_default_dimensions image =
  match source_dimensions image with
  | None -> Ok ()
  | Some (width, height) ->
      let current_width = Renderable.width image.renderable in
      let current_height = Renderable.height image.renderable in
      let set_width =
        if Float.compare current_width 0.0 > 0 then Ok ()
        else Renderable.set_width image.renderable (Yoga.Point (float_of_int width))
      in
      Result.bind set_width (fun () ->
          if Float.compare current_height 0.0 > 0 then Ok ()
          else
            Renderable.set_height image.renderable
              (Yoga.Point (float_of_int height)))

let install_source image source_value =
  match source_value with
  | None ->
      Option.iter Image.close image.image;
      image.image <- None;
      image.load_error <- None;
      Ok ()
  | Some (Native value) ->
      (match Image.retain value with
      | Error error ->
          image.load_error <- Some error;
          Option.iter (fun callback -> callback error) image.on_error;
          Ok ()
      | Ok retained ->
          let previous = image.image in
          image.image <- Some retained;
          image.load_error <- None;
          Option.iter Image.close previous;
          (match maybe_set_default_dimensions image with
          | Error error -> Error error
          | Ok () ->
              Option.iter (fun callback -> callback retained) image.on_load;
              Ok ()))
  | Some (Source source_value) ->
      (match Image.load source_value with
      | Error error ->
          image.load_error <- Some error;
          Option.iter (fun callback -> callback error) image.on_error;
          Ok ()
      | Ok loaded ->
          let previous = image.image in
          image.image <- Some loaded;
          image.load_error <- None;
          Option.iter Image.close previous;
          (match maybe_set_default_dimensions image with
          | Error error -> Error error
          | Ok () ->
              Option.iter (fun callback -> callback loaded) image.on_load;
              Ok ()))

let draw_image_to_buffer ~target ~image ~x ~y ~width ~height ~pixel_width
    ~pixel_height ~source_x ~source_y ~source_width ~source_height ~protocol =
  match target with
  | `Renderer buffer ->
      Buffer.draw_image buffer ~image ~x:(Int32.of_int x) ~y:(Int32.of_int y)
        ~width:(Int32.of_int width) ~height:(Int32.of_int height)
        ~pixel_width:(Int32.of_int pixel_width)
        ~pixel_height:(Int32.of_int pixel_height)
        ~source_x:(Int32.of_int source_x) ~source_y:(Int32.of_int source_y)
        ~source_width:(Int32.of_int source_width)
        ~source_height:(Int32.of_int source_height) ~protocol ()
  | `Owned buffer ->
      Owned_buffer.draw_image buffer ~image ~x ~y ~width ~height ~pixel_width
        ~pixel_height ~source_x ~source_y ~source_width ~source_height ~protocol
        ()

let render_self image renderable buffer _delta_time =
  let target_width = int_of_float (Float.floor (Renderable.width renderable)) in
  let target_height = int_of_float (Float.floor (Renderable.height renderable)) in
  let destination_x =
    int_of_float (Float.floor (Renderable.screen_x renderable))
  in
  let destination_y =
    int_of_float (Float.floor (Renderable.screen_y renderable))
  in
  let copy_frame_buffer () =
    match image.frame_buffer with
    | None -> Ok ()
    | Some frame_buffer ->
        Buffer.draw_frame_buffer buffer ~source:frame_buffer
          ~x:(Int32.of_int destination_x) ~y:(Int32.of_int destination_y) ()
  in
  let clear_result =
    match image.frame_buffer with
    | None -> Ok ()
    | Some frame_buffer ->
        Owned_buffer.clear frame_buffer ~background:Color.transparent
  in
  Result.bind clear_result (fun () ->
      match image.image with
      | None -> copy_frame_buffer ()
      | Some value ->
          let source_info = Image.get_info value in
          (match source_info with
          | Error error -> Error (image_error_to_core error)
          | Ok _info when target_width <= 0 || target_height <= 0 ->
              copy_frame_buffer ()
          | Ok info ->
              let aspect =
                context_cell_aspect_ratio (Renderable.context renderable)
              in
              let fitted_width, fitted_height =
                if (match image.fit with Cover -> true | Fit | Fill -> false) then
                  target_width, target_height
                else
                  fitted_size image ~target_width ~target_height
                    ~cell_aspect:aspect ()
              in
              if fitted_width <= 0 || fitted_height <= 0 then
                copy_frame_buffer ()
              else
                let draw_x, draw_y =
                  match image.frame_buffer with
                  | None ->
                      ( destination_x + ((target_width - fitted_width) / 2),
                        destination_y + ((target_height - fitted_height) / 2) )
                  | Some _ ->
                      ( (target_width - fitted_width) / 2,
                        (target_height - fitted_height) / 2 )
                in
                let pixel_width, pixel_height =
                  match
                    ( Render_context.pixel_resolution (Renderable.context renderable),
                      Render_context.width (Renderable.context renderable),
                      Render_context.height (Renderable.context renderable) )
                  with
                  | Ok (Some resolution), Ok terminal_width, Ok terminal_height
                    when Int32.compare terminal_width 0l > 0
                         && Int32.compare terminal_height 0l > 0 ->
                      ( max 1
                          (int_of_float
                             (Float.round
                                (float_of_int fitted_width
                                *. Int32.to_float resolution.width
                                /. Int32.to_float terminal_width))),
                        max 1
                          (int_of_float
                             (Float.round
                                (float_of_int fitted_height
                                *. Int32.to_float resolution.height
                                /. Int32.to_float terminal_height))) )
                  | _ -> 0, 0
                in
                let source_x, source_y, source_width, source_height =
                  if (match image.fit with Cover -> false | Fit | Fill -> true) then
                    0, 0, info.width, info.height
                  else
                    let target_aspect =
                      float_of_int target_width
                      /. (float_of_int target_height *. aspect)
                    in
                    let source_aspect =
                      float_of_int info.width /. float_of_int info.height
                    in
                    if Float.compare source_aspect target_aspect > 0 then
                      let width =
                        max 1
                          (int_of_float
                             (Float.round
                                (float_of_int info.height *. target_aspect)))
                      in
                      ((info.width - width) / 2, 0, width, info.height)
                    else
                      let height =
                        max 1
                          (int_of_float
                             (Float.round
                                (float_of_int info.width /. target_aspect)))
                      in
                      (0, (info.height - height) / 2, info.width, height)
                in
                let target =
                  match image.frame_buffer with
                  | None -> `Renderer buffer
                  | Some frame_buffer -> `Owned frame_buffer
                in
                let draw_result =
                  draw_image_to_buffer ~target ~image:value ~x:draw_x ~y:draw_y
                    ~width:fitted_width ~height:fitted_height ~pixel_width
                    ~pixel_height ~source_x ~source_y ~source_width
                    ~source_height
                    ~protocol:(resolve_protocol image.protocol
                                 (capabilities (Renderable.context renderable))
                                 ~has_resolution:(has_pixel_resolution
                                    (Renderable.context renderable)))
                in
                Result.bind draw_result (fun () -> copy_frame_buffer ())))

let resize_frame_buffer image ~width ~height =
  match image.frame_buffer with
  | None -> ()
  | Some frame_buffer ->
      ignore
        (Owned_buffer.resize frame_buffer ~width:(max 1 width)
           ~height:(max 1 height))

let create context ?id ?source ?(fit = Fit) ?(protocol = Image.Auto)
    ?(buffered = false) ?width ?height ?on_load ?on_error () =
  match Renderable.Private.create context ?id () with
  | Error error -> Error error
  | Ok renderable ->
      let dimension_result =
        Result.bind
          (match width with
          | None -> Ok ()
          | Some width when width > 0 ->
              Renderable.set_width renderable (Yoga.Point (float_of_int width))
          | Some _ -> Error Error.Invalid_argument)
          (fun () ->
            match height with
            | None -> Ok ()
            | Some height when height > 0 ->
                Renderable.set_height renderable (Yoga.Point (float_of_int height))
            | Some _ -> Error Error.Invalid_argument)
      in
      (match dimension_result with
      | Error error ->
          Renderable.destroy renderable;
          Error error
      | Ok () ->
          let buffer_id = Option.map (fun value -> value ^ "-image-buffer") id in
          let frame_result =
            if buffered then
              Owned_buffer.create ?id:buffer_id ~respect_alpha:true
                ~width:(Option.value width ~default:1)
                ~height:(Option.value height ~default:1) ()
              |> Result.map (fun value -> Some value)
            else Ok None
          in
          (match frame_result with
          | Error error ->
              Renderable.destroy renderable;
              Error error
          | Ok frame_buffer ->
              let value =
                {
                  renderable;
                  source = None;
                  image = None;
                  fit;
                  protocol;
                  load_error = None;
                  on_load;
                  on_error;
                  buffered;
                  frame_buffer;
                  destroyed = false;
                }
              in
              let behavior =
                Renderable.Private.make_behavior
                  ~render_self:(render_self value)
                  ~on_resize:(fun _renderable ~width ~height ->
                    resize_frame_buffer value ~width ~height;
                    ignore (Renderable.request_render value.renderable))
                  ~destroy_self:(fun _ ->
                    if not value.destroyed then begin
                      value.destroyed <- true;
                      Option.iter Image.close value.image;
                      value.image <- None;
                      Option.iter Owned_buffer.close value.frame_buffer
                    end)
                  ()
              in
              Renderable.Private.set_behavior renderable behavior;
              (match source with
              | None -> Ok value
              | Some source_value ->
                  value.source <- Some source_value;
                  (match install_source value (Some source_value) with
                  | Ok () ->
                      ignore (Renderable.request_render renderable);
                      Ok value
                  | Error error ->
                      Renderable.destroy renderable;
                      Error error))))

let set_source image value =
  match ensure_alive image with
  | Error error -> Error error
  | Ok () ->
      let previous = image.source in
      image.source <- value;
      (match install_source image value with
      | Ok () ->
          ignore (Renderable.request_render image.renderable);
          Ok ()
      | Error error ->
          image.source <- previous;
          Error error)

let set_fit image value =
  match ensure_alive image with
  | Error error -> Error error
  | Ok () -> image.fit <- value; Renderable.request_render image.renderable

let set_protocol image value =
  match ensure_alive image with
  | Error error -> Error error
  | Ok () -> image.protocol <- value; Renderable.request_render image.renderable

let effective_protocol image =
  resolve_protocol image.protocol (capabilities (Renderable.context image.renderable))
    ~has_resolution:(has_pixel_resolution (Renderable.context image.renderable))

let cell_aspect_ratio image =
  context_cell_aspect_ratio (Renderable.context image.renderable)
let get_fitted_size = fitted_size

let destroy image = Renderable.destroy image.renderable
