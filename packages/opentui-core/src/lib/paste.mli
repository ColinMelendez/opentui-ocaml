(** Paste decoding and terminal escape stripping. *)

type kind = Text | Binary | Unknown

type metadata = {
  mime_type : string option;
  kind : kind option;
}

val decode : bytes -> string
val strip_ansi : string -> string
