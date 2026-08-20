module Error = Error

module Native_token = Native_token

(* The pinned release constants are the source of truth for the configurator
   program under ../config; changing them requires updating both together. *)
let pinned_release_tag = "v29.0.1.1"

let pinned_release_version = "29.0.1.1"

type device = {
  instance : Native_token.Instance.t;
  adapter : Native_token.Adapter.t;
  queue : Native_token.Queue.t;
  handle : Native_token.Device.t;
  mutable closed : bool;
}

type render_target = {
  width : int;
  height : int;
  texture : Native_token.Texture.t;
  view : Native_token.Texture_view.t;
  mutable released : bool;
}

type readback = {
  stride : int;
  rows : int;
  buffer : Native_token.Buffer.t;
  mutable mapped : bool;
  mutable released : bool;
}

let rgba_bytes_per_pixel = 4

let readback_stride_alignment = 256

let texture_format_rgba8_unorm = Native.texture_format_rgba8_unorm_c ()

let texture_usage_render_attachment =
  Native.texture_usage_render_attachment_c ()

let texture_usage_copy_source = Native.texture_usage_copy_source_c ()

let buffer_usage_map_read = Native.buffer_usage_map_read_c ()

let buffer_usage_copy_destination =
  Native.buffer_usage_copy_destination_c ()

let readback_stride ~width =
  let unaligned = width * rgba_bytes_per_pixel in
  let aligned =
    ((unaligned + readback_stride_alignment - 1) / readback_stride_alignment)
    * readback_stride_alignment
  in
  aligned

let creation_result ~what = function
  | true, handle -> Ok handle
  | false, _ -> Error (Error.Creation_failed { what; code = 0; message = "" })

let request_result ~what = function
  | code, handle, _ when Int.equal code Native.request_status_success ->
      Ok handle
  | code, _, message ->
      Error (Error.Creation_failed { what; code; message })

let ( >>= ) result continuation =
  match result with
  | Ok value -> continuation value
  | Error _ as failure -> failure

let create_device () =
  match Native.instance_create () with
  | false, _ ->
      Error (Error.Creation_failed { what = "instance"; code = 0; message = "" })
  | true, instance -> (
      match
        request_result ~what:"adapter" (Native.instance_request_adapter instance)
      with
      | Error _ as failure ->
          Native.instance_release instance;
          failure
      | Ok adapter -> (
          match
            request_result ~what:"device"
              (Native.adapter_request_device instance adapter)
          with
          | Error _ as failure ->
              Native.adapter_release adapter;
              Native.instance_release instance;
              failure
          | Ok device_handle ->
              let queue = Native.device_get_queue device_handle in
              Ok
                {
                  instance;
                  adapter;
                  queue;
                  handle = device_handle;
                  closed = false;
                }))

let destroy_device device =
  if not device.closed then begin
    device.closed <- true;
    Native.queue_release device.queue;
    Native.device_release device.handle;
    Native.adapter_release device.adapter;
    Native.instance_release device.instance
  end

let is_closed device = device.closed

let check_open device operation =
  if device.closed then Error (Error.Closed { operation }) else Ok ()

let create_render_target device ~width ~height =
  check_open device "create_render_target" >>= fun () ->
  if width <= 0 || height <= 0 then
    Error (Error.Invalid_argument "render target dimensions must be positive")
  else
    Native.device_create_texture device.handle
      ( width,
        height,
        texture_format_rgba8_unorm,
        Int64.logor texture_usage_render_attachment texture_usage_copy_source )
    |> creation_result ~what:"texture"
    >>= fun texture ->
    match
      Native.texture_create_view texture |> creation_result ~what:"texture view"
    with
    | Ok view -> Ok { width; height; texture; view; released = false }
    | Error _ as failure ->
        Native.texture_release texture;
        failure

let destroy_render_target (target : render_target) =
  if not target.released then begin
    target.released <- true;
    Native.texture_view_release target.view;
    Native.texture_release target.texture
  end

let readback_size readback =
  Int64.to_int (Int64.mul (Int64.of_int readback.stride) (Int64.of_int readback.rows))

let create_readback device ~stride ~rows =
  check_open device "create_readback" >>= fun () ->
  if stride <= 0 || rows <= 0 then
    Error (Error.Invalid_argument "readback dimensions must be positive")
  else if stride mod readback_stride_alignment <> 0 then
    Error
      (Error.Invalid_argument
         (Printf.sprintf
            "readback stride %d violates the %d-byte copy alignment"
            stride readback_stride_alignment))
  else
    let size64 = Int64.mul (Int64.of_int stride) (Int64.of_int rows) in
    if
      Int64.compare size64 0L <= 0
      || not (Int64.equal (Int64.of_int (Int64.to_int size64)) size64)
    then Error (Error.Invalid_argument "readback size exceeds addressable bytes")
    else
      match
        creation_result ~what:"readback buffer"
          (Native.device_create_buffer device.handle
             ( size64,
               Int64.logor buffer_usage_map_read buffer_usage_copy_destination ))
      with
      | Ok buffer -> Ok { stride; rows; buffer; mapped = false; released = false }
      | Error _ as failure -> failure

let destroy_readback (buffer_view : readback) =
  if not buffer_view.released then begin
    buffer_view.released <- true;
    if buffer_view.mapped then begin
      Native.buffer_unmap buffer_view.buffer;
      buffer_view.mapped <- false
    end;
    Native.buffer_release buffer_view.buffer
  end

let submit_clear_frame device ~(target : render_target) ~(readback : readback)
    ~(color : floatarray) () =
  check_open device "submit_clear_frame" >>= fun () ->
  if target.released || readback.released then
    Error (Error.Closed { operation = "submit_clear_frame" })
  else if Float.Array.length color < rgba_bytes_per_pixel then
    Error (Error.Invalid_argument "clear color needs four channel values")
  else
    match
      creation_result ~what:"command encoder"
        (Native.device_create_command_encoder device.handle)
    with
    | Error _ as failure -> failure
    | Ok encoder ->
        Native.encoder_begin_render_pass_clear encoder target.view
          ( Float.Array.get color 0,
            Float.Array.get color 1,
            Float.Array.get color 2,
            Float.Array.get color 3 );
        Native.encoder_copy_texture_to_buffer encoder target.texture
          readback.buffer
          (target.width, target.height, readback.stride);
        let submit_result =
          match
            creation_result ~what:"command buffer"
              (Native.command_encoder_finish encoder)
          with
          | Error _ as failure -> failure
          | Ok command_buffer ->
              Native.queue_submit_one device.queue command_buffer;
              Native.command_buffer_release command_buffer;
              Ok ()
        in
        Native.command_encoder_release encoder;
        submit_result

let map_read device (readback : readback) =
  check_open device "map_read" >>= fun () ->
  if readback.released then
    Error (Error.Closed { operation = "map_read" })
  else if readback.mapped then
    Error (Error.Invalid_argument "readback is already mapped")
  else
    let status, message =
      Native.buffer_map_read_blocking device.handle readback.buffer
        ~size:(Int64.of_int (readback_size readback))
    in
    if Int.equal status Native.map_status_success then begin
      readback.mapped <- true;
      Ok ()
    end
    else
      Error
        (Error.Map_failed
           {
             code = status;
             message =
               (if String.length message = 0 then
                  "mapAsync did not report success"
                else message);
           })

let copy_mapped (readback : readback) destination =
  if readback.released then Error (Error.Closed { operation = "copy_mapped" })
  else if not readback.mapped then
    Error (Error.Invalid_argument "readback is not mapped")
  else
    let required = readback_size readback in
    if Bigarray.Array1.dim destination < required then
      Error
        (Error.Invalid_argument
           (Printf.sprintf
              "destination holds %d bytes but the mapped range has %d"
              (Bigarray.Array1.dim destination)
              required))
    else if
      Int.equal
        (Native.buffer_get_mapped_range_copy readback.buffer ~offset:0L
           ~size:(Int64.of_int required) destination)
        0
    then Error (Error.Native_failure { operation = "getMappedRange" })
    else Ok ()

let unmap (readback : readback) =
  if (not readback.released) && readback.mapped then begin
    Native.buffer_unmap readback.buffer;
    readback.mapped <- false
  end
