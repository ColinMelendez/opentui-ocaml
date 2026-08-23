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
  else if
    Int.compare readback.stride (readback_stride ~width:target.width) < 0
    || Int.compare readback.rows target.height < 0
  then
    Error
      (Error.Invalid_argument
         (Printf.sprintf
            "readback stride %d rows %d cannot hold a %dx%d frame"
            readback.stride readback.rows target.width target.height))
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

type shader_module = {
  handle : Native_token.Shader_module.t;
  mutable released : bool;
}

type bind_group_layout = {
  bgl_handle : Native_token.Bind_group_layout.t;
  mutable bgl_released : bool;
}

type pipeline_layout = {
  pl_handle : Native_token.Pipeline_layout.t;
  mutable pl_released : bool;
}

type render_pipeline = {
  rp_handle : Native_token.Render_pipeline.t;
  mutable rp_released : bool;
}

type bind_group = {
  bg_handle : Native_token.Bind_group.t;
  mutable bg_released : bool;
}

type draw_frame = {
  pipeline : render_pipeline;
  group : bind_group;
  vertex_buffer : Native_token.Buffer.t;
  vertex_size : int;
  index_buffer : Native_token.Buffer.t;
  index_size : int;
  index_count : int;
}

let submit_draw_frame device ~(target : render_target)
    ~(readback : readback)
    ~(clear : float * float * float * float) ~(draw : draw_frame) () =
  match check_open device "submit_draw_frame" with
  | Error _ as failure -> failure
  | Ok () -> (
      if target.released || readback.released then
        Error (Error.Closed { operation = "submit_draw_frame" })
      else if
        Int.compare readback.stride (readback_stride ~width:target.width) < 0
        || Int.compare readback.rows target.height < 0
      then
        Error
          (Error.Invalid_argument
             (Printf.sprintf
                "readback stride %d rows %d cannot hold a %dx%d frame"
                readback.stride readback.rows target.width target.height))
      else if
        draw.pipeline.rp_released || draw.group.bg_released
        || draw.vertex_size <= 0 || draw.index_size <= 0 || draw.index_count <= 0
      then
        Error (Error.Invalid_argument "draw frame references invalid state")
      else
        match
          creation_result ~what:"command encoder"
            (Native.device_create_command_encoder device.handle)
        with
        | Error _ as failure -> failure
        | Ok encoder ->
            let call : Native.draw_call =
              ( target.view,
                clear,
                draw.pipeline.rp_handle,
                draw.group.bg_handle,
                draw.vertex_buffer,
                Int64.of_int draw.vertex_size,
                draw.index_buffer,
                Int64.of_int draw.index_size,
                draw.index_count )
            in
            Native.encoder_render_draw_indexed encoder call;
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
            submit_result)

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

let create_buffer device ~(size : int) ~usage =
  match check_open device "create_buffer" with
  | Error _ as failure -> failure
  | Ok () ->
      if size <= 0 then
        Error (Error.Invalid_argument "buffer size must be positive")
      else
        creation_result ~what:"buffer"
          (Native.device_create_buffer device.handle
             (Int64.of_int size, usage))

let destroy_buffer (buffer : Native_token.Buffer.t) =
  Native.buffer_release buffer

let render_target_view (target : render_target) = target.view

let buffer_handle_string (buffer : Native_token.Buffer.t) : string =
  Int64.to_string buffer

let enable_diagnostics () = Native.enable_diagnostics ()

let drain_diagnostics ?(max = 16) () = Native.drain_diagnostics ~max

let buffer_usage_vertex = 0x20L

let buffer_usage_index = 0x10L

let buffer_usage_uniform = 0x40L

let create_shader_module device ~wgsl =
  match check_open device "create_shader_module" with
  | Error _ as failure -> failure
  | Ok () -> (
      match
        creation_result ~what:"shader module"
          (Native.device_create_shader_module device.handle ~wgsl)
      with
      | Ok handle -> Ok { handle; released = false }
      | Error _ as failure -> failure)

let destroy_shader_module module_ =
  if not module_.released then begin
    module_.released <- true;
    Native.shader_module_release module_.handle
  end

let create_uniform_bind_group_layout device =
  match check_open device "create_uniform_bind_group_layout" with
  | Error _ as failure -> failure
  | Ok () -> (
      match
        creation_result ~what:"bind group layout"
          (Native.device_create_uniform_bind_group_layout device.handle)
      with
      | Ok bgl_handle -> Ok { bgl_handle; bgl_released = false }
      | Error _ as failure -> failure)

let destroy_bind_group_layout layout =
  if not layout.bgl_released then begin
    layout.bgl_released <- true;
    Native.bind_group_layout_release layout.bgl_handle
  end

let create_pipeline_layout device (layout : bind_group_layout) =
  match check_open device "create_pipeline_layout" with
  | Error _ as failure -> failure
  | Ok () ->
      if layout.bgl_released then
        Error (Error.Closed { operation = "create_pipeline_layout" })
      else (
        match
          creation_result ~what:"pipeline layout"
            (Native.device_create_pipeline_layout device.handle
               layout.bgl_handle)
        with
        | Ok pl_handle -> Ok { pl_handle; pl_released = false }
        | Error _ as failure -> failure)

let destroy_pipeline_layout layout =
  if not layout.pl_released then begin
    layout.pl_released <- true;
    Native.pipeline_layout_release layout.pl_handle
  end

let create_render_pipeline device ~(layout : pipeline_layout)
    ~(shader : shader_module) ~vs_entry ~fs_entry ~target_format =
  match check_open device "create_render_pipeline" with
  | Error _ as failure -> failure
  | Ok () ->
      if layout.pl_released || shader.released then
        Error (Error.Closed { operation = "create_render_pipeline" })
      else
        match
          creation_result ~what:"render pipeline"
            (Native.device_create_render_pipeline device.handle
               ( layout.pl_handle,
                 shader.handle,
                 vs_entry,
                 fs_entry,
                 target_format ))
        with
        | Ok rp_handle -> Ok { rp_handle; rp_released = false }
        | Error _ as failure -> failure

let destroy_render_pipeline pipeline =
  if not pipeline.rp_released then begin
    pipeline.rp_released <- true;
    Native.render_pipeline_release pipeline.rp_handle
  end

let create_uniform_bind_group device (layout : bind_group_layout)
    (buffer : Native_token.Buffer.t) ~size =
  match check_open device "create_uniform_bind_group" with
  | Error _ as failure -> failure
  | Ok () ->
      if layout.bgl_released then
        Error (Error.Closed { operation = "create_uniform_bind_group" })
      else
        match
          creation_result ~what:"bind group"
            (Native.device_create_uniform_bind_group device.handle
               layout.bgl_handle buffer ~size:(Int64.of_int size))
        with
        | Ok bg_handle -> Ok { bg_handle; bg_released = false }
        | Error _ as failure -> failure

let destroy_bind_group group =
  if not group.bg_released then begin
    group.bg_released <- true;
    Native.bind_group_release group.bg_handle
  end

let write_buffer_string device buffer ~(offset : int) (data : string) =
  match check_open device "write_buffer_string" with
  | Error _ as failure -> failure
  | Ok () ->
      (* queueWriteBuffer requires the copy size to be a multiple of four;
         pad short tails so callers can stage compact index blocks. *)
      let pad = (4 - (String.length data mod 4)) mod 4 in
      let payload =
        if Int.equal pad 0 then data
        else data ^ String.make pad '\x00'
      in
      Native.queue_write_buffer_bytes device.queue buffer
        ~offset:(Int64.of_int offset) payload;
      Ok ()

(* Float32 little-endian packing into a byte string, suitable for vertex
   buffers and uniform blocks staged through queue writes. *)
let align4 n = ((n + 3) / 4) * 4

let pack_f32_le (values : floatarray) : string =
  let count = Float.Array.length values in
  Bytes.unsafe_to_string
    (Bytes.init (count * 4) (fun i ->
         let bits =
           Int32.bits_of_float (Float.Array.get values (i / 4))
         in
         let shift = (i mod 4) * 8 in
         Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical bits shift) 0xFFl))))

let pack_indices_u16 (indices : int array) : string =
  let bytes = Bytes.create (Array.length indices * 2) in
  Array.iteri
    (fun i index ->
      Bytes.set bytes (i * 2) (Char.chr (index land 0xff));
      Bytes.set bytes ((i * 2) + 1) (Char.chr ((index lsr 8) land 0xff)))
    indices;
  Bytes.unsafe_to_string bytes

let debug_triangle (device : device) : int =
  Native.debug_triangle_raw device.handle
