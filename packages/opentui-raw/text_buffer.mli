(** Native text storage used by OpenTUI text-buffer views. *)

type width_method = Wcwidth | Unicode
(** The reference terminal width algorithm. *)

type t
(** An explicitly owned native text buffer. *)

val create : width_method -> (t, Error.t) result
(** [create width_method] creates an empty native text buffer. *)

val clear : t -> (unit, Error.t) result
(** [clear buffer] removes all text while retaining the buffer resource. *)

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
