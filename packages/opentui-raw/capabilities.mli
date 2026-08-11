(** A copied capability snapshot for one renderer. *)

type unicode = Wcwidth | Unicode
(** The native Unicode width policy. *)

type multiplexer =
  | No_multiplexer
  | Tmux
  | Zellij
  | Screen
  | Unknown_multiplexer
(** The detected terminal multiplexer. *)

type image_protocol = Auto | Kitty | Sixel | Blocks
(** The selected image protocol. *)

type osc52_support = Unknown_osc52 | Supported | Unsupported
(** OSC 52 support reported by the terminal. *)

type terminal_info = {
  name : string;
  version : string;
  from_xtversion : bool;
}
(** Copied terminal name/version information. *)

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
(** Decoded terminal capabilities. All strings are owned copies. *)

(** [snapshot renderer] queries and decodes the renderer's capabilities. *)
val snapshot : Renderer.t -> (t, Error.t) result

(** [process_response renderer ~response] passes a caller-owned capability
    response synchronously to the native renderer. *)
val process_response :
  Renderer.t -> response:string -> (unit, Error.t) result
