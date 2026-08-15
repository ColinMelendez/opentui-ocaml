(** Text renderables with a separate text-composition tree. *)

type t
(** A measured retained text renderable. *)

val create :
  Render_context.t ->
  ?id:string ->
  ?width_method:Text_buffer.width_method ->
  ?wrap_mode:Text_buffer_view.wrap_mode ->
  ?content:Lib.Styled_text.t ->
  unit ->
  (t, Error.t) result
(** [create context ()] creates an empty text renderable. *)

val as_renderable : t -> Renderable.t
val text_node : t -> Text_node.t
val children : t -> Text_children.t
val get_text_children : t -> Text_node.t list
val content : t -> Lib.Styled_text.t
val selected_text : t -> (string, Error.t) result
val set_content : t -> Lib.Styled_text.t -> (unit, Error.t) result

val add :
  ?index:int -> t -> Text_children.child -> (int, Error.t) result
val remove : t -> Text_node.t -> (unit, Error.t) result
val insert_before :
  t -> Text_children.child -> anchor:Text_node.t -> (unit, Error.t) result
val clear : t -> (unit, Error.t) result

val destroy : t -> unit
