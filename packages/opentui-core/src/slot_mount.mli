(** A renderer-owned retained mount for one typed plugin slot. *)

type mode = Append | Replace | Single_winner

type fallback = unit -> (Slot_view.t list, Plugin_failure.t) result
type placeholder = Plugin_failure.t -> (Slot_view.t list, Plugin_failure.t) result

type 'props t

(** [create] constructs a detached mount. The caller attaches
    {!renderable} to its retained parent with {!Layout_children}. Fallback and
    placeholder factories are evaluated only when the selected mode needs
    their output. *)
val create :
  renderer:Renderer.t ->
  slot:'props Slot.t ->
  props:'props ->
  ?mode:mode ->
  ?fallback:fallback ->
  ?placeholder:placeholder ->
  unit ->
  ('props t, Plugin_failure.t) result

val renderable : 'props t -> Renderable.t
val mode : 'props t -> mode

(** Props are intentionally always treated as a new revision; no structural
    comparison is performed on the abstract props value. *)
val set_props : 'props t -> 'props -> (unit, Plugin_failure.t list) result
val set_mode : 'props t -> mode -> (unit, Plugin_failure.t list) result
val refresh : 'props t -> (unit, Plugin_failure.t list) result

(** [destroy] releases the subscription and every accepted view. It is
    idempotent. *)
val destroy : 'props t -> unit
val is_destroyed : 'props t -> bool
