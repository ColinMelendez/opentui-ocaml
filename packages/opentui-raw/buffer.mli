type t

val width : t -> (int32, Error.t) result
val height : t -> (int32, Error.t) result

val clear : t -> background:Color.t -> (unit, Error.t) result

val set_cell :
  t ->
  x:int32 ->
  y:int32 ->
  character:int32 ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
  (unit, Error.t) result

val draw_text :
  t ->
  text:string ->
  x:int32 ->
  y:int32 ->
  foreground:Color.t ->
  background:Color.t ->
  attributes:int32 ->
  (unit, Error.t) result

val write_resolved_chars :
  t ->
  output:bytes ->
  add_line_breaks:bool ->
  (int32, Error.t) result

module Private : sig
  val of_native : Native_token.Buffer.t -> Native_owner.t -> t
end
