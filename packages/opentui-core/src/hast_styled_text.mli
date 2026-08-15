type node =
  | Text of string
  | Element of { tag : string; classes : string list; children : node list }

val to_styled_text : syntax_style:Syntax_style.t -> ?base_highlight:string -> node -> Lib.Styled_text.t
