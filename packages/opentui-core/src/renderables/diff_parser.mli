type line_kind = Context | Added | Removed | Meta
type line = { kind : line_kind; text : string; old_number : int option; new_number : int option }
type hunk = { old_start : int; old_count : int; new_start : int; new_count : int; heading : string; lines : line list }
type patch = { old_file : string option; new_file : string option; hunks : hunk list }
type parse_error = Empty | Malformed of { line : int; message : string }

val parse : string -> (patch, parse_error) result
val unified_lines : patch -> line list
val line_text : line -> string
val is_context : line -> bool
val is_added : line -> bool
val is_removed : line -> bool
