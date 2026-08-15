type format = Unknown | Png | Raw_rgba | Jpeg | Webp | Gif

type color_status = Assumed_srgb | Explicit_srgb

type info = {
  width : int32;
  height : int32;
  source_width : int32;
  source_height : int32;
  format : format;
  color_status : color_status;
  orientation : int32;
  has_alpha : bool;
}

type resize_filter =
  | Default
  | Area
  | Triangle
  | Cubic_bspline
  | Catmull_rom
  | Mitchell
  | Nearest

type transform = Rotate_90 | Rotate_180 | Rotate_270 | Flip | Flop
type blend = Source_over | Source | Destination_over

type error =
  | Invalid_handle
  | Unsupported_format
  | Unsupported_color_space
  | Malformed_input
  | Dimension_limit
  | Memory_limit
  | Invalid_argument
  | Out_of_memory
  | Output_too_small
  | Internal_error
  | Unsupported_feature

type t = {
  handle : Native_token.Image.t;
  owner : Native_owner.t;
}

let error_of_status = function
  | 0 -> None
  | 1 -> Some Invalid_handle
  | 2 -> Some Unsupported_format
  | 3 -> Some Unsupported_color_space
  | 4 -> Some Malformed_input
  | 5 -> Some Dimension_limit
  | 6 -> Some Memory_limit
  | 7 -> Some Invalid_argument
  | 8 -> Some Out_of_memory
  | 9 -> Some Output_too_small
  | 10 -> Some Internal_error
  | 11 -> Some Unsupported_feature
  | _ -> Some Internal_error

let result_of_status status value =
  match error_of_status status with None -> Ok value | Some error -> Error error

let with_open image operation =
  if Native_owner.is_open image.owner then operation image.handle
  else Error Invalid_handle

let format_of_int = function
  | 0 -> Unknown
  | 1 -> Png
  | 2 -> Raw_rgba
  | 3 -> Jpeg
  | 4 -> Webp
  | 5 -> Gif
  | _ -> Unknown

let color_status_of_int = function
  | 1 -> Explicit_srgb
  | _ -> Assumed_srgb

let info_of_raw
    (width, height, source_width, source_height, format, color_status,
     orientation, has_alpha) =
  {
    width;
    height;
    source_width;
    source_height;
    format = format_of_int (Int32.to_int format);
    color_status = color_status_of_int (Int32.to_int color_status);
    orientation;
    has_alpha = not (Int32.equal has_alpha 0l);
  }

let info_raw image =
  let status, raw = Native.image_get_info image in
  result_of_status status (info_of_raw raw)

let create handle = { handle; owner = Native_owner.Private.create () }

let decode bytes =
  let status, handle = Native.image_decode bytes in
  match error_of_status status with
  | None -> Ok (create handle)
  | Some error -> Error error

let info bytes =
  let status, raw = Native.image_info bytes in
  result_of_status status (info_of_raw raw)

let create_from_rgba ~pixels ~width ~height ~stride =
  let status, handle =
    Native.image_create_from_rgba pixels (Int32.of_int width)
      (Int32.of_int height) (Int32.of_int stride)
  in
  match error_of_status status with
  | None -> Ok (create handle)
  | Some error -> Error error

let retain image =
  with_open image (fun handle ->
      let status, retained = Native.image_retain handle in
      result_of_status status (create retained))

let get_info image = with_open image info_raw

let materialize image =
  with_open image (fun handle ->
      result_of_status (Native.image_materialize handle) ())

let ensure_encoded_png image =
  with_open image (fun handle ->
      result_of_status (Native.image_ensure_encoded_png handle) ())

let clone image =
  with_open image (fun handle ->
      let status, cloned = Native.image_clone handle in
      result_of_status status (create cloned))

let copy_pixels image ~destination ~stride ~bgra =
  with_open image (fun handle ->
      result_of_status
        (Native.image_copy_pixels handle destination (Int32.of_int stride) bgra)
        ())

let resize_filter_to_int = function
  | Default -> 0l
  | Area -> 1l
  | Triangle -> 2l
  | Cubic_bspline -> 3l
  | Catmull_rom -> 4l
  | Mitchell -> 5l
  | Nearest -> 6l

let resize image ~width ~height ~filter =
  with_open image (fun handle ->
      let status, resized =
        Native.image_resize handle
          (Int32.of_int width, Int32.of_int height,
           resize_filter_to_int filter)
      in
      result_of_status status (create resized))

let extract image ~left ~top ~width ~height =
  with_open image (fun handle ->
      let status, extracted =
        Native.image_extract handle
          (Int32.of_int left, Int32.of_int top, Int32.of_int width,
           Int32.of_int height)
      in
      result_of_status status (create extracted))

let extend image ~top ~right ~bottom ~left ~background =
  with_open image (fun handle ->
      let status, extended =
        Native.image_extend handle
          ( Int32.of_int top,
            Int32.of_int right,
            Int32.of_int bottom,
            Int32.of_int left,
            background )
      in
      result_of_status status (create extended))

let transform_to_int = function
  | Rotate_90 -> 0l
  | Rotate_180 -> 1l
  | Rotate_270 -> 2l
  | Flip -> 3l
  | Flop -> 4l

let transform image operation =
  with_open image (fun handle ->
      let status, transformed =
        Native.image_transform handle (transform_to_int operation)
      in
      result_of_status status (create transformed))

let blend_to_int = function
  | Source_over -> 0l
  | Source -> 1l
  | Destination_over -> 2l

let composite base ~overlay ~left ~top ~blend ~opacity =
  with_open base (fun base_handle ->
      with_open overlay (fun overlay_handle ->
          let status, composited =
            Native.image_composite base_handle overlay_handle
              ( Int32.of_int left,
                Int32.of_int top,
                blend_to_int blend,
                Int32.of_int opacity )
          in
          result_of_status status (create composited)))

let close image =
  if Native_owner.is_open image.owner then begin
    Native.image_destroy image.handle;
    Native_owner.Private.close image.owner
  end

module Private = struct
  let with_open = with_open
  let handle image = image.handle
end
