module Styled = Lib.Styled_text
module Metrics = Lib.Text_metrics
module Types = Lib.Tree_sitter_types

type replacement = { start : int; end_ : int; text : string; group : string }
type style = { fg : Color.t option; bg : Color.t option; attributes : int }

let clamp value ~minimum ~maximum = max minimum (min maximum value)

let valid_range total highlight =
  let start = clamp highlight.Types.start ~minimum:0 ~maximum:total in
  let end_ = clamp highlight.end_ ~minimum:start ~maximum:total in
  start, end_

let specificity group =
  let count = ref 1 in
  String.iter (fun character -> if Char.equal character '.' then incr count) group;
  !count

let meta_flag meta field =
  match meta with None -> false | Some value -> field value

let style_for syntax_style base_highlight active =
  let active =
    List.sort
      (fun (left_index, left) (right_index, right) ->
        let specificity_order = Int.compare (specificity left.Types.group) (specificity right.group) in
        if Int.equal specificity_order 0 then Int.compare left_index right_index
        else specificity_order)
      active
  in
  let names =
    match base_highlight with
    | None -> List.map (fun (_, highlight) -> highlight.Types.group) active
    | Some base -> base :: List.map (fun (_, highlight) -> highlight.Types.group) active
  in
  let merged = Syntax_style.merge_styles syntax_style names in
  let fg = Option.bind merged.fg (fun color -> Result.to_option (Lib.Rgba.to_color color)) in
  let bg = Option.bind merged.bg (fun color -> Result.to_option (Lib.Rgba.to_color color)) in
  { fg; bg; attributes = merged.attributes }

let active_at highlights position =
  List.filter
    (fun (_, highlight) -> highlight.Types.start <= position && position < highlight.end_)
    highlights

let valid_active highlights position injection_ranges =
  let inside_injection =
    List.exists
      (fun (start, end_) -> start <= position && position < end_)
      injection_ranges
  in
  List.filter
    (fun (_, highlight) ->
        not
        (inside_injection
        && String.equal highlight.Types.group "markup.raw.block"
        && not (meta_flag highlight.meta (fun meta -> meta.is_injection))))
    (active_at highlights position)

let replacement_at replacements position =
  List.find_opt (fun replacement -> Int.equal replacement.start position) replacements

let replacements_of_highlights ~conceal ~total highlights content =
  if not conceal then []
  else
    List.filter_map
      (fun (_, highlight) ->
        let start, end_ = valid_range total highlight in
        if Int.equal start end_ then None
        else
          match highlight.Types.meta with
          | Some meta when Option.is_some meta.conceal ->
              Some { start; end_; text = Option.value meta.conceal ~default:""; group = highlight.group }
          | Some _ | None when String.equal highlight.group "conceal.with.space" ->
              Some { start; end_; text = " "; group = highlight.group }
          | Some _ | None when String.equal highlight.group "conceal" ->
              Some { start; end_; text = ""; group = highlight.group }
          | Some _ | None -> None)
      highlights

let additional_replacements ~total ~(codepoints : Metrics.codepoint array) content indexed_highlights =
  List.filter_map
    (fun (_, highlight) ->
      match highlight.Types.meta with
      | None -> None
      | Some meta ->
          let _, end_ = valid_range total highlight in
          if Option.is_some meta.conceal_lines && end_ < total
             && Char.equal (String.get content codepoints.(end_).byte_start) '\n'
          then Some { start = end_; end_ = end_ + 1; text = ""; group = highlight.group }
          else if Option.equal String.equal meta.conceal (Some " ")
                  && end_ < total
                  && Char.equal (String.get content codepoints.(end_).byte_start) ' '
          then Some { start = end_; end_ = end_ + 1; text = ""; group = highlight.group }
          else if Option.equal String.equal meta.conceal (Some "")
                  && String.equal highlight.group "conceal"
                  && not meta.is_injection
                  && end_ < total
                  && Char.equal (String.get content codepoints.(end_).byte_start) ' '
          then Some { start = end_; end_ = end_ + 1; text = ""; group = highlight.group }
          else None)
    indexed_highlights

let byte_start codepoints position total content =
  if Int.equal position total then String.length content
  else
    let codepoint : Metrics.codepoint = codepoints.(position) in
    codepoint.byte_start

let add_chunk chunks text style =
  if String.length text > 0 then
    chunks := Styled.chunk text ?fg:style.fg ?bg:style.bg ~attributes:style.attributes :: !chunks

let concealed_line_sources ~content ~highlights ~conceal =
  if not conceal then None
  else
    let codepoints = Metrics.scan Metrics.Unicode content in
    let total = Array.length codepoints in
    let ranges =
      List.filter_map
        (fun highlight ->
          let start, end_ = valid_range total highlight in
          let empty_conceal =
            match highlight.Types.meta with
            | Some meta -> Option.equal String.equal meta.conceal (Some "")
            | None -> String.equal highlight.group "conceal"
          in
          let conceal_lines =
            match highlight.Types.meta with
            | Some meta -> Option.is_some meta.conceal_lines
            | None -> false
          in
          if conceal_lines && empty_conceal && not (Int.equal start end_) then
            Some (start, end_)
          else None)
        highlights
    in
    if List.is_empty ranges then None
    else
      let line_sources = ref [] in
      let rendered_line_has_text = ref false in
      let set_current_source source has_text =
        match !line_sources with
        | [] -> line_sources := [ source ]
        | _ :: _ when not !rendered_line_has_text ->
            (match !line_sources with
            | _ :: tail -> line_sources := source :: tail
            | [] -> line_sources := [ source ])
        | _ -> line_sources := source :: !line_sources;
        if has_text then rendered_line_has_text := true
      in
      let source_line = ref 0 in
      let line_start = ref 0 in
      let range_index = ref 0 in
      while !line_start <= total do
        let newline = ref None in
        let position = ref !line_start in
        while !position < total && Option.is_none !newline do
          if Char.equal (String.get content codepoints.(!position).byte_start) '\n' then
            newline := Some !position
          else incr position
        done;
        let line_end = Option.value !newline ~default:total in
        while !range_index < List.length ranges
              && snd (List.nth ranges !range_index) <= !line_start do
          incr range_index
        done;
        let range = List.nth_opt ranges !range_index in
        let fully_concealed =
          match range with
          | Some (start, end_) -> line_end > !line_start && start <= !line_start && end_ >= line_end
          | None -> false
        in
        let line_break_concealed =
          match !newline, range with
          | Some newline, Some (start, end_) -> start <= newline && end_ >= newline
          | Some _, None | None, _ -> false
        in
        if not fully_concealed || not line_break_concealed then begin
          let has_text = line_end > !line_start && not fully_concealed in
          if has_text || Option.is_some !newline || not fully_concealed then
            set_current_source !source_line has_text;
          (match !newline with
          | Some _ when not line_break_concealed ->
              line_sources := (!source_line + 1) :: !line_sources;
              rendered_line_has_text := false
          | Some _ | None -> ())
        end;
        incr source_line;
        match !newline with
        | None -> line_start := total + 1
        | Some newline -> line_start := newline + 1
      done;
      if List.is_empty !line_sources then None
      else Some (Array.of_list (List.rev !line_sources))

let tree_sitter_to_styled_text ~syntax_style ?base_highlight ?(conceal = true) ~content ~highlights () =
  let codepoints = Metrics.scan Metrics.Unicode content in
  let total = Array.length codepoints in
  let normalized =
    List.filter_map
      (fun (index, highlight) ->
        let start, end_ = valid_range total highlight in
        if Int.equal start end_ then None else Some (index, { highlight with start; end_ }))
      (List.mapi (fun index highlight -> index, highlight) highlights)
  in
  let injection_ranges =
    List.filter_map
      (fun (_, highlight) ->
        if meta_flag highlight.Types.meta (fun meta -> meta.contains_injection) then
          Some (highlight.Types.start, highlight.end_)
        else None)
      normalized
  in
  let replacements =
    List.sort
      (fun left right -> Int.compare left.start right.start)
      (replacements_of_highlights ~conceal ~total normalized content
      @ additional_replacements ~total ~codepoints content normalized)
  in
  let chunks = ref [] in
  let position = ref 0 in
  while !position < total do
    match replacement_at replacements !position with
    | Some replacement ->
        let style = style_for syntax_style base_highlight
            (valid_active normalized !position injection_ranges) in
        add_chunk chunks replacement.text style;
        position := replacement.end_
    | None ->
        let next = ref (!position + 1) in
        let active = valid_active normalized !position injection_ranges in
        List.iter
          (fun (_, highlight) ->
            if highlight.Types.start > !position && highlight.start < !next then next := highlight.start;
            if highlight.end_ > !position && highlight.end_ < !next then next := highlight.end_)
          normalized;
        let start_byte = byte_start codepoints !position total content in
        let end_byte = byte_start codepoints !next total content in
        add_chunk chunks (String.sub content start_byte (end_byte - start_byte))
          (style_for syntax_style base_highlight active);
        position := !next
  done;
  if Int.equal total 0 then Styled.of_string "" else Styled.create (List.rev !chunks)
