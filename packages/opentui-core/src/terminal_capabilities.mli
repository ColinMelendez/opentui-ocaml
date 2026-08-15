(** A typed snapshot of terminal capabilities owned by one renderer. *)

type unicode = Wcwidth | Unicode
(** The terminal's Unicode width policy. *)

type multiplexer =
  | No_multiplexer
  | Tmux
  | Zellij
  | Screen
  | Unknown_multiplexer
(** The detected terminal multiplexer. *)

type image_protocol = Auto | Kitty | Sixel | Blocks
(** The selected terminal image protocol. *)

type osc52_support = Unknown_osc52 | Supported | Unsupported
(** The terminal's reported OSC 52 support. *)

type terminal_info = {
  name : string;
  version : string;
  from_xtversion : bool;
}
(** Copied terminal name and version information. *)

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
(** A renderer-owned, immutable capability snapshot. *)
