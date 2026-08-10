type t

val create : node:Layout.Node.t -> text:string -> t
val text : t -> string
val set_text : t -> text:string -> unit

val draw :
  t ->
  Renderer.Frame.t ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
  (unit, Error.t) result
