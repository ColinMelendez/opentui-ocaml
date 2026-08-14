(** Native text storage used by text-buffer renderables. *)

type width_method = Wcwidth | Unicode
(** The terminal character-width policy used by native text measurement. *)

type t = Text_buffer_internal.t
(** An explicitly owned native text buffer. *)

val create : width_method -> (t, Error.t) result
(** [create width_method] creates an empty text buffer. *)

val clear : t -> (unit, Error.t) result
(** [clear buffer] removes all text while retaining the buffer resource. *)

val append : t -> string -> (unit, Error.t) result
(** [append buffer text] appends UTF-8 text to [buffer]. *)

val set_text : t -> string -> (unit, Error.t) result
(** [set_text buffer text] replaces the text stored in [buffer]. *)

val length : t -> (int32, Error.t) result
(** [length buffer] returns the native character count. *)

val byte_size : t -> (int32, Error.t) result
(** [byte_size buffer] returns the native UTF-8 byte count. *)

val close : t -> (unit, Error.t) result
(** [close buffer] releases [buffer] when it has no open views. *)
