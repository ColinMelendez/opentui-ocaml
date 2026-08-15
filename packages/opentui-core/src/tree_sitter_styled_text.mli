val tree_sitter_to_styled_text :
  syntax_style:Syntax_style.t ->
  ?base_highlight:string ->
  ?conceal:bool ->
  content:string ->
  highlights:Lib.Tree_sitter_types.highlight list ->
  unit ->
  Lib.Styled_text.t

val concealed_line_sources :
  content:string ->
  highlights:Lib.Tree_sitter_types.highlight list ->
  conceal:bool ->
  int array option
