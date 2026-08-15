type screen_mode = Alternate_screen | Main_screen | Split_footer

type t = {
  effective_footer_height : int;
  render_offset : int;
  render_width : int;
  render_height : int;
}

let calculate mode ~terminal_width ~terminal_height ~footer_height =
  let safe_width = max terminal_width 0 in
  let safe_height = max terminal_height 0 in
  match mode with
  | Alternate_screen | Main_screen ->
      {
        effective_footer_height = 0;
        render_offset = 0;
        render_width = safe_width;
        render_height = safe_height;
      }
  | Split_footer ->
      let effective_footer_height = min (max footer_height 0) safe_height in
      {
        effective_footer_height;
        render_offset = safe_height - effective_footer_height;
        render_width = safe_width;
        render_height = effective_footer_height;
      }
