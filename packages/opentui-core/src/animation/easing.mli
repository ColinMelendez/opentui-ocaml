type t =
  | Linear
  | In_quad
  | Out_quad
  | In_out_quad
  | In_expo
  | Out_expo
  | In_out_sine
  | Out_bounce
  | Out_elastic
  | In_bounce
  | In_circ
  | Out_circ
  | In_out_circ
  | In_back
  | Out_back
  | In_out_back

val linear : t
val in_quad : t
val out_quad : t
val in_out_quad : t
val in_expo : t
val out_expo : t
val in_out_sine : t
val out_bounce : t
val out_elastic : t
val in_bounce : t
val in_circ : t
val out_circ : t
val in_out_circ : t
val in_back : t
val out_back : t
val in_out_back : t

(** [apply easing progress] clamps [progress] to [0., 1.] before evaluating
    the built-in easing curve. Overshooting curves may return values outside
    that interval. *)
val apply : t -> float -> float

val eval : t -> float -> float
