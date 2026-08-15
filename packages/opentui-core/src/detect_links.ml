module Styled = Lib.Styled_text
module Types = Lib.Tree_sitter_types

type range = { start : int; end_ : int; url : string }

let is_url_start content index =
  let starts prefix =
    let prefix_length = String.length prefix in
    index + prefix_length <= String.length content
    && String.equal (String.sub content index prefix_length) prefix
  in
  starts "https://" || starts "http://" || starts "www."

let is_url_character character =
  let code = Char.code character in
  (code >= Char.code 'A' && code <= Char.code 'Z')
  || (code >= Char.code 'a' && code <= Char.code 'z')
  || (code >= Char.code '0' && code <= Char.code '9')
  || Char.equal character ':' || Char.equal character '/'
  || Char.equal character '.' || Char.equal character '-'
  || Char.equal character '_' || Char.equal character '~'
  || Char.equal character '?' || Char.equal character '#'
  || Char.equal character '[' || Char.equal character ']'
  || Char.equal character '@' || Char.equal character '!'
  || Char.equal character '$' || Char.equal character '&'
  || Char.equal character '\'' || Char.equal character '('
  || Char.equal character ')' || Char.equal character '*'
  || Char.equal character '+' || Char.equal character ','
  || Char.equal character ';' || Char.equal character '='
  || Char.equal character '%'

let scan_plain_urls content =
  let codepoints = Lib.Text_metrics.scan Lib.Text_metrics.Unicode content in
  let total = Array.length codepoints in
  let result = ref [] in
  let position = ref 0 in
  while !position < total do
    let byte = codepoints.(!position).byte_start in
    if is_url_start content byte then begin
      let finish = ref (!position + 1) in
      while !finish < total && is_url_character (String.get content codepoints.(!finish).byte_start) do incr finish done;
      let end_byte = if Int.equal !finish total then String.length content else codepoints.(!finish).byte_start in
      result := { start = !position; end_ = !finish; url = String.sub content byte (end_byte - byte) } :: !result;
      position := !finish
    end else incr position
  done;
  List.rev !result

let codepoint_text content (codepoints : Lib.Text_metrics.codepoint array) start end_ =
  let start_byte = codepoints.(start).byte_start in
  let end_byte =
    if Int.equal end_ (Array.length codepoints) then String.length content
    else codepoints.(end_).byte_start
  in
  String.sub content start_byte (end_byte - start_byte)

let is_url_group group =
  String.equal group "markup.link.url" || String.equal group "string.special.url"

let starts_with value prefix =
  String.length value >= String.length prefix
  && String.equal (String.sub value 0 (String.length prefix)) prefix

let link_label_range ~content codepoints total previous url_range =
  let rec find = function
    | [] -> None
    | highlight :: rest ->
        if String.equal highlight.Types.group "markup.link.label" then
          let start = max 0 (min total highlight.start) in
          let end_ = max start (min total highlight.end_) in
          if Int.equal start end_ then find rest
          else Some { start; end_; url = url_range.url }
        else if starts_with highlight.Types.group "markup.link" then find rest
        else None
  in
  ignore content;
  ignore codepoints;
  find previous

let ranges ~content ~highlights =
  let codepoints = Lib.Text_metrics.scan Lib.Text_metrics.Unicode content in
  let total = Array.length codepoints in
  let rec syntax_ranges previous remaining result =
    match remaining with
    | [] -> List.rev result
    | highlight :: rest when is_url_group highlight.Types.group ->
        let start = max 0 (min total highlight.start) in
        let end_ = max start (min total highlight.end_) in
        let result =
          if Int.equal start end_ then result
          else
            let range = { start; end_; url = codepoint_text content codepoints start end_ } in
            let result = range :: result in
            match link_label_range ~content codepoints total previous range with
            | None -> result
            | Some label -> label :: result
        in
        syntax_ranges (highlight :: previous) rest result
    | highlight :: rest -> syntax_ranges (highlight :: previous) rest result
  in
  match syntax_ranges [] highlights [] with
  | [] -> scan_plain_urls content
  | values -> values

let apply ~content ~styled_text ranges =
  if List.is_empty ranges then styled_text
  else
    let codepoints = Lib.Text_metrics.scan Lib.Text_metrics.Unicode content in
    let total = Array.length codepoints in
    let plain = Styled.plain_text styled_text in
    if not (String.equal plain content) then styled_text
    else
      let ranges =
        List.filter_map
          (fun range ->
            let start = max 0 (min total range.start) in
            let end_ = max start (min total range.end_) in
            if Int.equal start end_ then None else Some { range with start; end_ })
          ranges
      in
      let sorted_ranges = List.sort (fun left right -> Int.compare left.start right.start) ranges in
      let append_chunk result (chunk : Styled.chunk) start_pos =
        let chunk_codepoints = Lib.Text_metrics.scan Lib.Text_metrics.Unicode chunk.text in
        let chunk_length = Array.length chunk_codepoints in
        let finish_pos = start_pos + chunk_length in
        let byte_at_chunk position =
          if Int.equal position chunk_length then String.length chunk.text
          else chunk_codepoints.(position).byte_start
        in
        let rec append_segments result local_pos =
          if local_pos >= chunk_length then result
          else
            let global_pos = start_pos + local_pos in
            let next = ref finish_pos in
            List.iter
              (fun range ->
                if range.start > global_pos && range.start < !next then next := range.start;
                if range.end_ > global_pos && range.end_ < !next then next := range.end_)
              sorted_ranges;
            let next_local = min chunk_length (!next - start_pos) in
            let active =
              List.find_opt
                (fun range -> range.start <= global_pos && global_pos < range.end_)
                sorted_ranges
            in
            let start_byte = byte_at_chunk local_pos in
            let end_byte = byte_at_chunk next_local in
            let text = String.sub chunk.text start_byte (end_byte - start_byte) in
            let link = match active with None -> chunk.link | Some range -> Some range.url in
            let piece =
              Styled.chunk text ?fg:chunk.fg ?bg:chunk.bg
                ~attributes:chunk.attributes ?link
            in
            append_segments (piece :: result) next_local
        in
        append_segments result 0, finish_pos
      in
      let result = ref [] in
      let content_pos = ref 0 in
      List.iter
        (fun chunk ->
          let pieces, finish = append_chunk !result chunk !content_pos in
          result := pieces;
          content_pos := finish)
        (Styled.chunks styled_text);
      Styled.create (List.rev !result)
