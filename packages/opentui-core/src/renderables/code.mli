type highlight_state =
  | Idle
  | Pending
  | Applied
  | Fallback of Lib.Tree_sitter_types.parser_error
(** [Pending] means the current generation has either been admitted to the
    background executor or is the one latest snapshot queued behind admitted
    work. Failed admission does not enter [Pending]. *)

type highlight_context = {
  content : string;
  filetype : string;
  syntax_style : Syntax_style.t;
}

type chunks_context = {
  content : string;
  filetype : string;
  syntax_style : Syntax_style.t;
  highlights : Lib.Tree_sitter_types.highlight list;
}

type t

val create :
  Render_context.t ->
  ?id:string ->
  ?content:string ->
  ?filetype:string ->
  ?syntax_style:Syntax_style.t ->
  ?tree_sitter_client:Lib.Tree_sitter_client.t ->
  ?background:Platform.Eio_runtime.Background.submitter ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?conceal:bool ->
  ?draw_unstyled_text:bool ->
  ?streaming:bool ->
  ?initial_styled_text:Lib.Styled_text.t ->
  ?base_highlight:string ->
  ?on_highlight:(Lib.Tree_sitter_types.highlight list ->
    highlight_context ->
    (Lib.Tree_sitter_types.highlight list, Lib.Tree_sitter_types.parser_error)
    result) ->
  ?on_chunks:(Lib.Styled_text.t ->
    chunks_context ->
    (Lib.Styled_text.t, Lib.Tree_sitter_types.parser_error) result) ->
  unit ->
  (t, Error.t) result

val as_renderable : t -> Renderable.t
val text_buffer_renderable : t -> Text_buffer_renderable.t
val content : t -> string
val set_content : t -> string -> (unit, Error.t) result
val filetype : t -> string option
val set_filetype : t -> string option -> (unit, Error.t) result
val syntax_style : t -> Syntax_style.t
val set_syntax_style : t -> Syntax_style.t -> (unit, Error.t) result
val tree_sitter_client : t -> Lib.Tree_sitter_client.t option
val set_tree_sitter_client : t -> Lib.Tree_sitter_client.t option -> (unit, Error.t) result
val conceal : t -> bool
val set_conceal : t -> bool -> (unit, Error.t) result
val draw_unstyled_text : t -> bool
val set_draw_unstyled_text : t -> bool -> (unit, Error.t) result
val streaming : t -> bool
val set_streaming : t -> bool -> (unit, Error.t) result
val highlights : t -> Lib.Tree_sitter_types.highlight list
val highlight_state : t -> highlight_state
val highlighting_done : t -> unit Eio.Promise.t
val refresh : t -> (unit, Error.t) result
val line_info : t -> (Text_buffer_view.line_info, Error.t) result
val logical_line_info : t -> (Text_buffer_view.line_info, Error.t) result
val virtual_line_count : t -> (int, Error.t) result
val selected_text : t -> (string, Error.t) result
val set_selection : t -> start:int -> end_:int -> unit -> (unit, Error.t) result
val set_wrap_mode : t -> Text_buffer_view.wrap_mode -> (unit, Error.t) result
val wrap_mode : t -> Text_buffer_view.wrap_mode
val scroll_x : t -> int
val scroll_y : t -> int
val set_scroll : t -> x:int -> y:int -> (unit, Error.t) result
val destroy : t -> unit
(** [destroy code] destroys {!as_renderable}. Destroying that renderable
    directly performs the same one-shot Code cleanup. *)
