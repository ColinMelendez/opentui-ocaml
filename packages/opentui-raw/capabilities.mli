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

val snapshot : Renderer.t -> (t, Error.t) result

val process_response :
  Renderer.t -> response:string -> (unit, Error.t) result
