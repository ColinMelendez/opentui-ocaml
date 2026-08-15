type inline =
  | Text of string
  | Emphasis of inline list
  | Strong of inline list
  | Delete of inline list
  | Code_span of string
  | Link of { label : inline list; href : string }
  | Image of { alt : string; href : string }
  | Hard_break

type alignment = Align_left | Align_center | Align_right | Align_default

type list_item = { raw : string; inlines : inline list }

type token =
  | Heading of { level : int; raw : string; inlines : inline list }
  | Paragraph of { raw : string; inlines : inline list }
  | Code_block of { raw : string; language : string option; text : string }
  | Blockquote of { raw : string; inlines : inline list }
  | Unordered_list of { raw : string; items : list_item list }
  | Ordered_list of { raw : string; start : int; items : list_item list }
  | Table of { raw : string; headers : inline list list; rows : inline list list list; alignments : alignment list }
  | Horizontal_rule of string
  | Html of string

type parsed

val parse : string -> parsed
val parse_incremental : ?trailing_unstable:int -> string -> parsed option -> parsed
val content : parsed -> string
val tokens : parsed -> token list
val stable_token_count : parsed -> int
val token_raw : token -> string
val inline_text : inline list -> string
