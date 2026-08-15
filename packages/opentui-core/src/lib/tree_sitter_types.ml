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

type parser_error = No_parser of string | Failed of string

type parser = {
  filetype : string;
  aliases : string list;
  highlight : string -> (highlight list, parser_error) result;
}

type request = {
  generation : int;
  filetype : string;
  content : string;
}
