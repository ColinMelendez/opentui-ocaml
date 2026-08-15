(** Named syntax styles and deterministic style merging. *)

type style_definition = {
  fg : Lib.Rgba.t option;
  bg : Lib.Rgba.t option;
  bold : bool option;
  italic : bool option;
  underline : bool option;
  dim : bool option;
}

type style_definition_input = {
  fg : Lib.Rgba.t option;
  bg : Lib.Rgba.t option;
  bold : bool option;
  italic : bool option;
  underline : bool option;
  dim : bool option;
}

type merged_style = { fg : Lib.Rgba.t option; bg : Lib.Rgba.t option; attributes : int }

type theme_token = {
  foreground : Lib.Rgba.t option;
  background : Lib.Rgba.t option;
  bold : bool option;
  italic : bool option;
  underline : bool option;
  dim : bool option;
}

type theme_token_style = {
  scope : string list;
  style : theme_token;
}

type t

val create : unit -> t
val from_styles : (string * style_definition_input) list -> t
val from_theme : theme_token_style list -> t
val convert_theme_to_styles : theme_token_style list -> (string * style_definition) list

val register_style : t -> string -> style_definition_input -> int
val resolve_style_id : t -> string -> int option
val get_style_id : t -> string -> int option
val style_count : t -> int
val get_style : t -> string -> style_definition option
val merge_styles : t -> string list -> merged_style
val clear_cache : t -> unit
val cache_size : t -> int
val all_styles : t -> (string * style_definition) list
val registered_names : t -> string list
val destroy : t -> unit
val is_destroyed : t -> bool

module Private : sig
  val native : t -> Opentui_raw.Syntax_style.t option
end
