(** Border styles and packed drawing data used by {!Renderables.Box}. *)

type style = Single | Double | Rounded | Heavy
(** The four border styles provided by the reference renderer. *)

type side = Top | Right | Bottom | Left
(** A selectable border side. *)

type border = No_border | All_borders | Sides of side list
(** A complete border selection. *)

type alignment = Left | Center | Right
(** Horizontal title alignment. *)

type sides = {
  top : bool;
  right : bool;
  bottom : bool;
  left : bool;
}
(** The normalized side selection used by layout and scissor calculations. *)

type characters
(** Eleven native border code points in the reference order. *)

val no_border : border
val all_borders : border
val to_sides : border -> sides
val top : sides -> bool
val right : sides -> bool
val bottom : sides -> bool
val left : sides -> bool
val characters : style -> characters

val of_codepoints : int32 array -> (characters, Error.t) result
(** [of_codepoints values] copies exactly eleven nonnegative code points. *)

module Private : sig
  val to_native : characters -> int32 array

  val pack_draw_options :
    border:border ->
    should_fill:bool ->
    title_alignment:alignment ->
    bottom_title_alignment:alignment ->
    int32
end
