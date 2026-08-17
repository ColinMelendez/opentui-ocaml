type protocol = Auto | Kitty | Sixel | Blocks

type format =
  | Unknown
  | Png
  | Raw_rgba
  | Jpeg
  | Webp
  | Gif

type color_status = Assumed_srgb | Explicit_srgb

type info = {
  width : int;
  height : int;
  source_width : int;
  source_height : int;
  format : format;
  color_status : color_status;
  orientation : int;
  has_alpha : bool;
}

type read_operation = Stat | Open | Read

type read_error =
  | Io of { operation : read_operation; detail : string }
  | Too_large of { limit : int }

type decode_error =
  | Invalid_argument
  | Native of Opentui_raw.Image.error

type error =
  | Closed
  | Invalid_argument
  | Native of Opentui_raw.Image.error

type load_error =
  | Read of read_error
  | Decode of decode_error
  | Native of error
  | Core of Error.t

type source =
  | Encoded of bytes
  | Rgba of { pixels : bytes; width : int; height : int; stride : int }
  | Path of Eio.Fs.dir_ty Eio.Path.t

type raw = {
  data : bytes;
  width : int;
  height : int;
  stride : int;
  bgra : bool;
}

type t = {
  raw : Opentui_raw.Image.t;
  mutable closed : bool;
}

let map_format = function
  | Opentui_raw.Image.Unknown -> Unknown
  | Png -> Png
  | Raw_rgba -> Raw_rgba
  | Jpeg -> Jpeg
  | Webp -> Webp
  | Gif -> Gif

let map_color_status = function
  | Opentui_raw.Image.Assumed_srgb -> Assumed_srgb
  | Explicit_srgb -> Explicit_srgb

let map_info (info : Opentui_raw.Image.info) =
  {
    width = Int32.to_int info.width;
    height = Int32.to_int info.height;
    source_width = Int32.to_int info.source_width;
    source_height = Int32.to_int info.source_height;
    format = map_format info.format;
    color_status = map_color_status info.color_status;
    orientation = Int32.to_int info.orientation;
    has_alpha = info.has_alpha;
  }

let make raw = { raw; closed = false }

let of_decode_result
    (result : (Opentui_raw.Image.t, Opentui_raw.Image.error) result) :
    (t, decode_error) result =
  match result with
  | Ok raw -> Ok (make raw)
  | Error error -> Error (Native error)

let of_raw_result
    (result : (Opentui_raw.Image.t, Opentui_raw.Image.error) result) :
    (t, error) result =
  match result with
  | Ok raw -> Ok (make raw)
  | Error error -> Error (Native error)

let max_path_bytes = 64 * 1024 * 1024

let operation_message = function
  | Stat -> "stat"
  | Open -> "open"
  | Read -> "read"

let message = function
  | Closed -> "the image owner is closed"
  | Invalid_argument -> "an image argument is invalid"
  | Native error ->
      "native image operation: " ^ Opentui_raw.Image.message error

let pp formatter error = Format.pp_print_string formatter (message error)

let read_message = function
  | Io { operation; detail } ->
      Printf.sprintf "image %s failed: %s" (operation_message operation) detail
  | Too_large { limit } ->
      Printf.sprintf "image source exceeds the %d-byte limit" limit

let read_pp formatter error = Format.pp_print_string formatter (read_message error)

let decode_message (error : decode_error) =
  match error with
  | Invalid_argument -> "an encoded image argument is invalid"
  | Native error -> "native image decode: " ^ Opentui_raw.Image.message error

let decode_pp formatter error =
  Format.pp_print_string formatter (decode_message error)

let load_message (error : load_error) =
  match error with
  | Read error -> read_message error
  | Decode error -> decode_message error
  | Native error -> "image native operation: " ^ message error
  | Core error -> "image owner operation: " ^ Error.message error

let load_pp formatter error = Format.pp_print_string formatter (load_message error)

let read_path path =
  let read_contents flow =
    let buffer = Stdlib.Buffer.create 65536 in
    let chunk_size = 65536 in
    let total = ref 0 in
    let finished = ref false in
    let error = ref None in
    while not !finished && Option.is_none !error do
      let remaining = max_path_bytes - !total in
      let capacity =
        if Int.equal remaining 0 then 1 else min chunk_size remaining
      in
      let chunk = Cstruct.create capacity in
      let count =
        try Eio.Flow.single_read flow chunk with End_of_file -> 0
      in
      if Int.equal count 0 then finished := true
      else if Int.equal remaining 0 then
        error := Some (Too_large { limit = max_path_bytes })
      else begin
        Stdlib.Buffer.add_string buffer (Cstruct.to_string chunk ~len:count);
        total := !total + count
      end
    done;
    match !error with
    | Some error -> Error error
    | None -> Ok (Bytes.of_string (Stdlib.Buffer.contents buffer))
  in
  let read_with_flow flow =
    try read_contents flow with
    | (Eio.Io _ as exception_value) ->
        Error
          (Io
             {
               operation = Read;
               detail = Printexc.to_string exception_value;
             })
  in
  try
    let stat = Eio.Path.stat ~follow:true path in
    if
      Optint.Int63.compare stat.size (Optint.Int63.of_int max_path_bytes) > 0
    then Error (Too_large { limit = max_path_bytes })
    else
      Eio.Switch.run @@ fun sw ->
      try read_with_flow (Eio.Path.open_in ~sw path) with
      | (Eio.Io _ as exception_value) ->
          Error
            (Io
               {
                 operation = Open;
                 detail = Printexc.to_string exception_value;
               })
  with
  | (Eio.Io _ as exception_value) ->
      Error
        (Io
           {
             operation = Stat;
             detail = Printexc.to_string exception_value;
           })

let decode bytes : (t, decode_error) result =
  if Bytes.length bytes = 0 then Error Invalid_argument
  else of_decode_result (Opentui_raw.Image.decode (Bytes.copy bytes))

let info bytes : (info, decode_error) result =
  if Bytes.length bytes = 0 then Error Invalid_argument
  else
    match Opentui_raw.Image.info (Bytes.copy bytes) with
    | Ok value -> Ok (map_info value)
    | Error error -> Error (Native error)

let from_rgba ~pixels ~width ~height ~stride : (t, decode_error) result =
  if width <= 0 || height <= 0 || stride < width * 4
  then Error Invalid_argument
  else
    of_decode_result
      (Opentui_raw.Image.create_from_rgba ~pixels:(Bytes.copy pixels) ~width
         ~height ~stride)

let load source =
  match source with
  | Encoded bytes ->
      Result.map_error (fun error -> Decode error) (decode bytes)
  | Rgba { pixels; width; height; stride } ->
      Result.map_error (fun error -> Decode error)
        (from_rgba ~pixels ~width ~height ~stride)
  | Path path ->
      (match read_path path with
      | Error error -> Error (Read error)
      | Ok bytes ->
          Result.map_error (fun error -> Decode error) (decode bytes))

let ensure_open image = if image.closed then Error Closed else Ok ()

let close image =
  if not image.closed then begin
    image.closed <- true;
    Opentui_raw.Image.close image.raw
  end

let get_info image =
  match ensure_open image with
  | Error error -> Error error
  | Ok () ->
      (match Opentui_raw.Image.get_info image.raw with
      | Ok value -> Ok (map_info value)
      | Error error -> Error (Native error))

let width image = Result.map (fun (value : info) -> value.width) (get_info image)
let height image = Result.map (fun (value : info) -> value.height) (get_info image)

let source_width image =
  Result.map (fun (value : info) -> value.source_width) (get_info image)

let source_height image =
  Result.map (fun (value : info) -> value.source_height) (get_info image)

let retain image =
  match ensure_open image with
  | Error error -> Error error
  | Ok () ->
      of_raw_result (Opentui_raw.Image.retain image.raw)

let clone image =
  match ensure_open image with
  | Error error -> Error error
  | Ok () -> of_raw_result (Opentui_raw.Image.clone image.raw)

let materialize image =
  match ensure_open image with
  | Error error -> Error error
  | Ok () ->
      (match Opentui_raw.Image.materialize image.raw with
      | Ok () -> Ok ()
      | Error error -> Error (Native error))

let ensure_encoded_png image =
  match ensure_open image with
  | Error error -> Error error
  | Ok () ->
      (match Opentui_raw.Image.ensure_encoded_png image.raw with
      | Ok () -> Ok ()
      | Error error -> Error (Native error))

let copy_to image ~destination ~stride ?(bgra = false) () =
  match ensure_open image with
  | Error error -> Error error
  | Ok () ->
      (match
         Opentui_raw.Image.copy_pixels image.raw ~destination ~stride ~bgra
       with
      | Ok () -> Ok ()
      | Error error -> Error (Native error))

let copy image ?(bgra = false) () =
  match get_info image with
  | Error error -> Error error
  | Ok info ->
      let stride = info.width * 4 in
      let destination = Bytes.create (stride * info.height) in
      (match copy_to image ~destination ~stride ~bgra () with
      | Ok () -> Ok (destination, stride)
      | Error error -> Error error)

let resize_filter_to_raw = function
  | `Default -> Opentui_raw.Image.Default
  | `Area -> Area
  | `Triangle -> Triangle
  | `Cubic_bspline -> Cubic_bspline
  | `Catmull_rom -> Catmull_rom
  | `Mitchell -> Mitchell
  | `Nearest -> Nearest

let rec resize image ?width ?height ?(filter = `Area) () =
  match width, height with
  | None, None -> Error Invalid_argument
  | Some width, Some height when width <= 0 || height <= 0 ->
      Error Invalid_argument
  | Some width, Some height ->
      (match ensure_open image with
      | Error error -> Error error
      | Ok () ->
          of_raw_result
            (Opentui_raw.Image.resize image.raw ~width ~height
               ~filter:(resize_filter_to_raw filter)))
  | Some width, None ->
      (match get_info image with
      | Error error -> Error error
      | Ok info ->
          let height =
            max 1
              (int_of_float
                 (Float.round
                    (float_of_int info.height *. float_of_int width
                    /. float_of_int info.width)))
          in
          resize image ~width ~height ~filter ())
  | None, Some height ->
      (match get_info image with
      | Error error -> Error error
      | Ok info ->
          let width =
            max 1
              (int_of_float
                 (Float.round
                    (float_of_int info.width *. float_of_int height
                    /. float_of_int info.height)))
          in
          resize image ~width ~height ~filter ())

let take_raw image ?(bgra = false) () =
  match get_info image with
  | Error error -> Error error
  | Ok info ->
      (match materialize image with
      | Error error -> Error error
      | Ok () ->
          (match copy image ~bgra () with
          | Error error -> Error error
          | Ok (data, stride) ->
              close image;
              Ok { data; width = info.width; height = info.height; stride; bgra }))

let extract image ~left ~top ~width ~height =
  if left < 0 || top < 0 || width <= 0 || height <= 0 then Error Invalid_argument
  else
    match ensure_open image with
    | Error error -> Error error
    | Ok () ->
        of_raw_result
          (Opentui_raw.Image.extract image.raw ~left ~top ~width ~height)

let extend image ?(top = 0) ?(right = 0) ?(bottom = 0) ?(left = 0)
    ?(background = Bytes.of_string "\000\000\000\255") () =
  if top < 0 || right < 0 || bottom < 0 || left < 0 || Bytes.length background <> 4
  then Error Invalid_argument
  else
    match ensure_open image with
    | Error error -> Error error
    | Ok () ->
        of_raw_result
          (Opentui_raw.Image.extend image.raw ~top ~right ~bottom ~left
             ~background)

let transform image operation =
  match ensure_open image with
  | Error error -> Error error
  | Ok () ->
      let operation =
        match operation with
        | `Rotate_90 -> Opentui_raw.Image.Rotate_90
        | `Rotate_180 -> Rotate_180
        | `Rotate_270 -> Rotate_270
        | `Flip -> Flip
        | `Flop -> Flop
      in
      of_raw_result (Opentui_raw.Image.transform image.raw operation)

let composite base ~overlay ?(left = 0) ?(top = 0) ?(blend = `Source_over)
    ?(opacity = 255) () =
  if opacity < 0 || opacity > 255 then Error Invalid_argument
  else
    match ensure_open base, ensure_open overlay with
    | Error error, _ | _, Error error -> Error error
    | Ok (), Ok () ->
        let blend =
          match blend with
          | `Source_over -> Opentui_raw.Image.Source_over
          | `Source -> Source
          | `Destination_over -> Destination_over
        in
        of_raw_result
          (Opentui_raw.Image.composite base.raw ~overlay:overlay.raw ~left ~top
             ~blend ~opacity)

module Private = struct
  let with_open image operation =
    Opentui_raw.Image.Private.with_open image.raw operation
  let raw image = image.raw
end
