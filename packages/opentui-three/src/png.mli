(** Minimal PNG emission for renderer screenshots. Private to the library;
    the facade's save-to-file path is its only consumer and its output is
    pinned by decoding through Opentui_core.Image. *)

val encode_rgba : string -> width:int -> height:int -> string
(** [encode_rgba data ~width ~height] wraps tightly packed 8-bit RGBA rows
    in a valid PNG (no filtering, stored deflate). *)
