(** Native text storage used by OpenTUI text-buffer views. *)

type width_method = Wcwidth | Unicode
type styled_chunk = Native.styled_chunk
(** The reference terminal width algorithm. *)

type t
(** An explicitly owned native text buffer. *)

val create : width_method -> (t, Error.t) result
(** [create width_method] creates an empty native text buffer. *)

val clear : t -> (unit, Error.t) result
(** [clear buffer] removes all text while retaining the buffer resource. *)

val reset : t -> (unit, Error.t) result
(** [reset buffer] removes text and native retained-memory registrations while
    preserving defaults and syntax configuration. *)

val set_styled_text : t -> styled_chunk list -> (unit, Error.t) result
val clear_all_highlights : t -> (unit, Error.t) result
type highlight = {
  start : int32;
  end_ : int32;
  style_id : int32;
  priority : int;
  hl_ref : int;
}
val add_highlight_by_char_range : t -> highlight -> (unit, Error.t) result
val add_highlight : t -> line:int -> highlight -> (unit, Error.t) result
val remove_highlights_by_ref : t -> int -> (unit, Error.t) result
val clear_line_highlights : t -> int -> (unit, Error.t) result
val set_default_fg : t -> Color.t option -> (unit, Error.t) result
val set_default_bg : t -> Color.t option -> (unit, Error.t) result
val set_default_attributes : t -> int32 option -> (unit, Error.t) result
val reset_defaults : t -> (unit, Error.t) result
val set_syntax_style : t -> Syntax_style.t option -> (unit, Error.t) result

val append : t -> bytes -> (unit, Error.t) result
(** [append buffer bytes] copies UTF-8 bytes into the native buffer. Each
    non-empty append consumes one of the 255 native memory-registry slots for
    the lifetime of [buffer]. An exhausted registry returns
    [Error.Native_failure]; the input remains retained by the OCaml owner but
    is not appended. *)

val set_text : t -> bytes -> (unit, Error.t) result
(** [set_text buffer bytes] replaces the native buffer contents. *)

val length : t -> (int32, Error.t) result
(** [length buffer] returns the native character length. *)

val byte_size : t -> (int32, Error.t) result
(** [byte_size buffer] returns the native UTF-8 byte size. *)

val line_count : t -> (int32, Error.t) result
(** [line_count buffer] returns the native logical line count. *)

val load_file : t -> string -> (unit, Error.t) result
(** [load_file buffer path] replaces the buffer with the file at [path]. *)

val tab_width : t -> (int32, Error.t) result
val set_tab_width : t -> int32 -> (unit, Error.t) result

val close : t -> (unit, Error.t) result
(** [close buffer] destroys a buffer with no open views. *)

module Private : sig
  val with_open :
    t ->
    (Native_token.Text_buffer.t -> ('a, Error.t) result) ->
    ('a, Error.t) result
  val owner : t -> Native_owner.t
  val is_open : t -> bool
  val register_view : t -> unit
  val unregister_view : t -> unit
end
