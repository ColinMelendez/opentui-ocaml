(** Global terminal selection state shared by the renderer and selectable
    renderables. *)

type point = { x : float; y : float }
type bounds = { x : float; y : float; width : float; height : float }
type selectable = { id : int; x : float; y : float; destroyed : bool; text : string }

type t

val create : anchor:point -> focus:point -> t
val anchor : t -> point
val focus : t -> point
val set_focus : t -> point -> unit
val is_start : t -> bool
val set_is_start : t -> bool -> unit
val is_active : t -> bool
val set_active : t -> bool -> unit
val is_dragging : t -> bool
val set_dragging : t -> bool -> unit
val bounds : t -> bounds

val selected_renderables : t -> selectable list
val touched_renderables : t -> selectable list
val update_selected_renderables : t -> selectable list -> unit
val update_touched_renderables : t -> selectable list -> unit

val selected_text : t -> string

type local_bounds = {
  anchor_x : float;
  anchor_y : float;
  focus_x : float;
  focus_y : float;
  is_active : bool;
}

val convert_global_to_local : t option -> local_x:float -> local_y:float -> local_bounds option
