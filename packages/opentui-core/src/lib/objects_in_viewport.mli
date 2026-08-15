(** Culling of layout objects against a terminal viewport. *)

type viewport = { x : float; y : float; width : float; height : float }
type direction = Row | Column

type 'a object_ = {
  value : 'a;
  screen_x : float;
  screen_y : float;
  width : float;
  height : float;
  z_index : int;
}

val get :
  ?direction:direction ->
  ?padding:float ->
  ?min_trigger_size:int ->
  viewport ->
  'a object_ list ->
  'a object_ list
