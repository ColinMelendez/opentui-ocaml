type range = { start : int; end_ : int; url : string }

val ranges : content:string -> highlights:Lib.Tree_sitter_types.highlight list -> range list
val apply : content:string -> styled_text:Lib.Styled_text.t -> range list -> Lib.Styled_text.t
