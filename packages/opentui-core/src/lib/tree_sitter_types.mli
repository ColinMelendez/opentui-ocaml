(** Typed, synchronous equivalents of the reference Tree-sitter worker
    messages. Offsets are UTF-8 codepoint offsets, not JavaScript UTF-16
    offsets. *)

type highlight_meta = {
  is_injection : bool;
  injection_lang : string option;
  contains_injection : bool;
  conceal : string option;
  conceal_lines : string option;
}

type highlight = {
  start : int;
  end_ : int;
  group : string;
  meta : highlight_meta option;
}

type parser_error =
  | No_parser of string
  | Failed of string

type worker_safety = Owner_only | Worker_safe

type parser = {
  filetype : string;
  aliases : string list;
  worker_safety : worker_safety;
  highlight : string -> (highlight list, parser_error) result;
}
