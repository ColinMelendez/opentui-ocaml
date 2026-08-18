type table_options = {
  show_borders : bool;
  outer_border : bool;
  cell_padding_x : int;
  cell_padding_y : int;
  column_width_mode : Text_table.column_width_mode;
}

type t

val create :
  Render_context.t ->
  ?id:string ->
  ?content:string ->
  ?syntax_style:Syntax_style.t ->
  ?fg:Color.t ->
  ?bg:Color.t ->
  ?tree_sitter_client:Lib.Tree_sitter_client.t ->
  ?background:Platform.Eio_runtime.Background.submitter ->
  ?conceal:bool ->
  ?conceal_code:bool ->
  ?streaming:bool ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?table_options:table_options ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val content : t -> string
val set_content : t -> string -> (unit, Error.t) result
val syntax_style : t -> Syntax_style.t
val set_syntax_style : t -> Syntax_style.t -> (unit, Error.t) result
val conceal : t -> bool
val set_conceal : t -> bool -> (unit, Error.t) result
val conceal_code : t -> bool
val set_conceal_code : t -> bool -> (unit, Error.t) result
val streaming : t -> bool
val set_streaming : t -> bool -> (unit, Error.t) result
val parse_state : t -> Markdown_parser.parsed
val block_count : t -> int
val stable_block_count : t -> int
val selected_text : t -> (string, Error.t) result
val destroy : t -> unit
