type t

val create : unit -> t
val register_parser : t -> Tree_sitter_types.parser -> (unit, Tree_sitter_types.parser_error) result
val remove_parser : t -> string -> unit
val resolve_parser : t -> string -> Tree_sitter_types.parser option
val parser_names : t -> string list
val clear : t -> unit
val destroy : t -> unit
val is_destroyed : t -> bool

val begin_request : t -> content:string -> filetype:string -> Tree_sitter_types.request
val highlight_request : t -> Tree_sitter_types.request -> (Tree_sitter_types.highlight list, Tree_sitter_types.parser_error) result
val is_current : t -> Tree_sitter_types.request -> bool
val highlight_once : t -> content:string -> filetype:string -> (Tree_sitter_types.highlight list, Tree_sitter_types.parser_error) result
