type node =
  | Text of string
  | Element of { tag : string; classes : string list; children : node list }

let to_styled_text ~syntax_style ?base_highlight root =
  let rec visit inherited node =
    match node with
    | Text text ->
        let merged = Syntax_style.merge_styles syntax_style inherited in
        let fg = Option.bind merged.fg (fun color -> Result.to_option (Lib.Rgba.to_color color)) in
        let bg = Option.bind merged.bg (fun color -> Result.to_option (Lib.Rgba.to_color color)) in
        [ Lib.Styled_text.chunk text ?fg ?bg ~attributes:merged.attributes ]
    | Element { tag; classes; children } ->
        let tag_style =
          if String.equal tag "" then [] else [ "markup." ^ tag ]
        in
        let names =
          (match base_highlight with None -> [] | Some value -> [ value ])
          @ inherited @ tag_style @ classes
        in
        List.concat_map (visit names) children
  in
  Lib.Styled_text.create (visit [] root)
