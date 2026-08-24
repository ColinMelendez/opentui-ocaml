(** A CPU-side RGBA texture with wrap and filter controls. The renderer
    uploads it once per instance; mutating [pixels] in place requires a
    fresh {!create} to be observed - GPU state keys on this record's
    identity, matching the geometry-upload contract. *)

type t = {
  pixels : bytes;
  width : int;
  height : int;
  wrap_s : [ `Repeat | `Clamp ];
  wrap_t : [ `Repeat | `Clamp ];
  filter : [ `Nearest | `Linear ];
}

val pixels : t -> bytes

val width : t -> int

val height : t -> int

val create :
  pixels:bytes ->
  width:int ->
  height:int ->
  ?wrap_s:[ `Repeat | `Clamp ] ->
  ?wrap_t:[ `Repeat | `Clamp ] ->
  ?filter:[ `Nearest | `Linear ] ->
    unit -> (t, string) result
(** Validates tight packing ([width * height * 4] bytes) and positive
    dimensions; defaults match the reference loader: repeat wrapping,
    nearest filtering. *)
