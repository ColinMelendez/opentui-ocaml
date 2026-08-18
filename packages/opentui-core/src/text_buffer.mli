(** Native text storage used by text-buffer renderables. *)

type width_method = Wcwidth | Unicode

type highlight = {
  start : int;
  end_ : int;
  style_id : int;
  priority : int option;
  hl_ref : int option;
}
(** The terminal character-width policy used by native text measurement. *)

type t = Text_buffer_internal.t
(** An explicitly owned native text buffer. *)

val create : width_method -> (t, Error.t) result
(** [create width_method] creates an empty text buffer. *)

val clear : t -> (unit, Error.t) result
(** [clear buffer] removes all text while retaining the buffer resource. *)

val reset : t -> (unit, Error.t) result
(** [reset buffer] clears text, highlights, and native retained-memory state
    while preserving defaults, syntax style, and tab width. *)

val append : t -> string -> (unit, Error.t) result
(** [append buffer text] appends UTF-8 text to [buffer]. *)

val set_text : t -> string -> (unit, Error.t) result
(** [set_text buffer text] replaces the text stored in [buffer]. *)

val load_file : t -> path:string -> (unit, Error.t) result
(** [load_file buffer ~path] replaces the text with the file at [path]. *)

val set_styled_text : t -> Lib.Styled_text.t -> (unit, Error.t) result
(** [set_styled_text] stores the plain text and materializes its style chunks
    as native style spans. The buffer must have a {!Syntax_style.t} attached
    with {!set_syntax_style} before this call for foreground colors,
    backgrounds, attributes, and links to be rendered by a view. *)

val text : t -> (string, Error.t) result
(** [text buffer] returns the current UTF-8 text retained by the core owner. *)

val plain_text : t -> (string, Error.t) result

val text_range : t -> start_offset:int -> end_offset:int -> (string, Error.t) result
(** [text_range] uses display-width offsets and snaps to UTF-8 boundaries. *)

val line_count : t -> (int, Error.t) result
val styled_text : t -> (Lib.Styled_text.t option, Error.t) result

val set_default_fg : t -> Color.t option -> (unit, Error.t) result
val default_fg : t -> (Color.t option, Error.t) result
val set_default_bg : t -> Color.t option -> (unit, Error.t) result
val default_bg : t -> (Color.t option, Error.t) result
val set_default_attributes : t -> int option -> (unit, Error.t) result
val default_attributes : t -> (int option, Error.t) result
val reset_defaults : t -> (unit, Error.t) result

val set_syntax_style : t -> Syntax_style.t option -> (unit, Error.t) result
val syntax_style : t -> (Syntax_style.t option, Error.t) result

val add_highlight : t -> line:int -> highlight -> (unit, Error.t) result
val add_highlight_by_char_range : t -> highlight -> (unit, Error.t) result
val remove_highlights_by_ref : t -> int -> (unit, Error.t) result
val clear_line_highlights : t -> int -> (unit, Error.t) result
val clear_all_highlights : t -> (unit, Error.t) result
val line_highlights : t -> int -> (highlight list, Error.t) result
val highlight_count : t -> (int, Error.t) result

val set_tab_width : t -> int -> (unit, Error.t) result
val tab_width : t -> (int, Error.t) result

val length : t -> (int32, Error.t) result
(** [length buffer] returns the native character count. *)

val byte_size : t -> (int32, Error.t) result
(** [byte_size buffer] returns the native UTF-8 byte count. *)

val close : t -> (unit, Error.t) result
(** [close buffer] releases [buffer] when it has no open views. *)
