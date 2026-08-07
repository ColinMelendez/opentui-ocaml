type unicode = Wcwidth | Unicode

type multiplexer =
  | No_multiplexer
  | Tmux
  | Zellij
  | Screen
  | Unknown_multiplexer

type image_protocol = Auto | Kitty | Sixel | Blocks

type osc52_support = Unknown_osc52 | Supported | Unsupported

type terminal_info = {
  name : string;
  version : string;
  from_xtversion : bool;
}

type t = {
  kitty_keyboard : bool;
  kitty_graphics : bool;
  rgb : bool;
  ansi256 : bool;
  unicode : unicode;
  sgr_pixels : bool;
  color_scheme_updates : bool;
  explicit_width : bool;
  scaled_text : bool;
  sixel : bool;
  focus_tracking : bool;
  sync : bool;
  bracketed_paste : bool;
  hyperlinks : bool;
  osc52 : bool;
  notifications : bool;
  explicit_cursor_positioning : bool;
  remote : bool;
  multiplexer : multiplexer;
  image_protocol : image_protocol;
  terminal : terminal_info;
  osc52_support : osc52_support;
}

let error_of_status status =
  match Error.Private.of_native_status status with
  | Some error -> error
  | None -> Error.Native_failure

let decode_unicode code =
  match code with
  | 0 -> Ok Wcwidth
  | 1 -> Ok Unicode
  | _ -> Error Error.Native_failure

let decode_multiplexer code =
  match code with
  | 0 -> Ok No_multiplexer
  | 1 -> Ok Tmux
  | 2 -> Ok Zellij
  | 3 -> Ok Screen
  | 4 -> Ok Unknown_multiplexer
  | _ -> Error Error.Native_failure

let decode_image_protocol code =
  match code with
  | 0 -> Ok Auto
  | 1 -> Ok Kitty
  | 2 -> Ok Sixel
  | 3 -> Ok Blocks
  | _ -> Error Error.Native_failure

let decode_osc52_support code =
  match code with
  | 0 -> Ok Unknown_osc52
  | 1 -> Ok Supported
  | 2 -> Ok Unsupported
  | _ -> Error Error.Native_failure

let decode native =
  let (
      kitty_keyboard,
      kitty_graphics,
      rgb,
      ansi256,
      unicode_code,
      sgr_pixels,
      color_scheme_updates,
      explicit_width,
      scaled_text,
      sixel,
      focus_tracking,
      sync,
      bracketed_paste,
      hyperlinks,
      osc52,
      notifications,
      explicit_cursor_positioning,
      remote,
      multiplexer_code,
      image_protocol_code,
      name,
      version,
      from_xtversion,
      osc52_support_code) =
    native
  in
  match decode_unicode unicode_code with
  | Error error -> Error error
  | Ok unicode ->
      (match decode_multiplexer multiplexer_code with
      | Error error -> Error error
      | Ok multiplexer ->
          (match decode_image_protocol image_protocol_code with
          | Error error -> Error error
          | Ok image_protocol ->
              (match decode_osc52_support osc52_support_code with
              | Error error -> Error error
              | Ok osc52_support ->
                  Ok
                    {
                      kitty_keyboard;
                      kitty_graphics;
                      rgb;
                      ansi256;
                      unicode;
                      sgr_pixels;
                      color_scheme_updates;
                      explicit_width;
                      scaled_text;
                      sixel;
                      focus_tracking;
                      sync;
                      bracketed_paste;
                      hyperlinks;
                      osc52;
                      notifications;
                      explicit_cursor_positioning;
                      remote;
                      multiplexer;
                      image_protocol;
                      terminal = { name; version; from_xtversion };
                      osc52_support;
                    })))

let snapshot renderer =
  Renderer.Private.with_open renderer (fun handle ->
      let status, native = Native.renderer_capabilities handle in
      match status, native with
      | 0, Some fields -> decode fields
      | 0, None -> Error Error.Native_failure
      | _, _ -> Error (error_of_status status))

let process_response renderer ~response =
  Renderer.Private.with_open renderer (fun handle ->
      let status = Native.process_capability_response handle response in
      match status with
      | 0 -> Ok ()
      | _ -> Error (error_of_status status))
