(** Terminal geometry used by the renderer and split-footer hosts. *)

type screen_mode = Alternate_screen | Main_screen | Split_footer

type t = {
  effective_footer_height : int;
  render_offset : int;
  render_width : int;
  render_height : int;
}

val calculate :
  screen_mode -> terminal_width:int -> terminal_height:int -> footer_height:int -> t
