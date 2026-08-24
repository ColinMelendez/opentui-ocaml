(** Procedural texture generators, port of the reference TextureUtils
    generators (the file loader arrives with the image-decode bridge). *)

val checkerboard : size:int -> squares:int -> ?a:char -> ?b:char -> unit -> Texture.t
(** [squares] by [squares] alternating cells of two RGBA byte-quadruples,
    each cell one pixel of the [size] by [size] texture. *)

val gradient :
  kind:[ `Horizontal | `Vertical | `Radial ] ->
  size:int ->
  from:(int * int * int) ->
  to_:(int * int * int) ->
    unit -> Texture.t
(** Linear interpolation between two opaque RGB colors across the texture;
    radial interpolates on distance from the center. *)

val octave_noise : seed:int -> octaves:int -> size:int -> Texture.t
(** Deterministic value noise summed over power-of-two octaves, encoded as
    grayscale. Same seed and parameters produce identical bytes. *)
