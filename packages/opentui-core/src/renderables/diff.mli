type view = Unified | Split
type t

val create :
  Render_context.t ->
  ?id:string ->
  ?content:string ->
  ?view:view ->
  ?filetype:string ->
  ?syntax_style:Syntax_style.t ->
  ?tree_sitter_client:Lib.Tree_sitter_client.t ->
  ?background:Platform.Eio_runtime.Background.submitter ->
  ?sync_scroll:bool ->
  ?show_line_numbers:bool ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val content : t -> string
val set_content : t -> string -> (unit, Error.t) result
val view : t -> view
val set_view : t -> view -> (unit, Error.t) result
val sync_scroll : t -> bool
val set_sync_scroll : t -> bool -> (unit, Error.t) result
val show_line_numbers : t -> bool
val set_show_line_numbers : t -> bool -> (unit, Error.t) result
val parse_error : t -> Diff_parser.parse_error option
val patch : t -> Diff_parser.patch option
val hunk_count : t -> int
val left_code : t -> Code.t option
val right_code : t -> Code.t option
val selected_text : t -> (string, Error.t) result
val destroy : t -> unit
