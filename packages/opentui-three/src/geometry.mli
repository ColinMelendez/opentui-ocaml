type t = {
  interleaved : floatarray;
  indices : int array;
}
(** Triangle geometry in the renderer's fixed vertex layout: six floats per
    vertex - position xyz followed by normal xyz - and u16 indices. The
    renderer uploads both once per geometry instance. *)

val interleaved : t -> floatarray

val indices : t -> int array
