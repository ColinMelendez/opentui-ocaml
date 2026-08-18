module Parser = Markdown_parser
module Styled = Lib.Styled_text

type table_options = {
  show_borders : bool;
  outer_border : bool;
  cell_padding_x : int;
  cell_padding_y : int;
}

type block_entry = {
  token : Parser.token;
  renderable : Renderable.t;
  selected_text : unit -> (string, Error.t) result;
}

type rendered_block = {
  renderable : Renderable.t;
  selected_text : unit -> (string, Error.t) result;
}

type t = {
  renderable : Renderable.t;
  children : Layout_children.t;
  context : Render_context.t;
  mutable content : string;
  mutable syntax_style : Syntax_style.t;
  owns_syntax_style : bool;
  fg : Color.t option;
  bg : Color.t option;
  tree_sitter_client : Lib.Tree_sitter_client.t option;
  background : Platform.Eio_runtime.Background.submitter option;
  mutable conceal : bool;
  mutable conceal_code : bool;
  mutable streaming : bool;
  wrap_mode : Text_buffer_view.wrap_mode;
  table_options : table_options;
  mutable parse_state : Parser.parsed;
  mutable blocks : block_entry list;
  mutable destroyed : bool;
}

let as_renderable markdown = markdown.renderable
let content markdown = markdown.content
let syntax_style markdown = markdown.syntax_style
let conceal markdown = markdown.conceal
let conceal_code markdown = markdown.conceal_code
let parse_state markdown = markdown.parse_state
let block_count markdown = List.length markdown.blocks
let stable_block_count markdown = Parser.stable_token_count markdown.parse_state

let ensure_alive markdown = if markdown.destroyed then Error Error.Destroyed else Ok ()

let register_default_styles syntax_style =
  let definition ?fg ?bg ?(bold = false) ?(italic = false) ?(underline = false)
      ?(dim = false) () =
    { Syntax_style.fg; bg; bold = Some bold; italic = Some italic; underline = Some underline; dim = Some dim }
  in
  let add name value = if Option.is_none (Syntax_style.get_style_id syntax_style name) then ignore (Syntax_style.register_style syntax_style name value) in
  let green = Lib.Rgba.from_ints 34 197 94 in
  let blue = Lib.Rgba.from_ints 96 165 250 in
  List.iter
    (fun (name, value) -> add name value)
    [
      ("markup.heading", definition ~bold:true ());
      ("markup.strong", definition ~bold:true ());
      ("markup.italic", definition ~italic:true ());
      ("markup.strikethrough", definition ~dim:true ());
      ("markup.raw", definition ~bg:(Lib.Rgba.from_ints 40 40 40) ());
      ("markup.link.label", definition ~fg:blue ~underline:true ());
      ("punctuation.special", definition ~fg:green ());
    ]

let style_chunk ?link syntax_style names text =
  let merged = Syntax_style.merge_styles syntax_style names in
  let fg = Option.bind merged.fg (fun value -> Result.to_option (Lib.Rgba.to_color value)) in
  let bg = Option.bind merged.bg (fun value -> Result.to_option (Lib.Rgba.to_color value)) in
  Styled.chunk text ?link ?fg ?bg ~attributes:merged.attributes

let rec inline_chunks syntax_style ~conceal inherited values =
  List.concat_map
    (function
      | Parser.Text text -> [ style_chunk syntax_style inherited text ]
      | Parser.Emphasis values ->
          let styled = inline_chunks syntax_style ~conceal (inherited @ [ "markup.italic" ]) values in
          if conceal then styled
          else
            style_chunk syntax_style (inherited @ [ "markup.italic" ]) "*"
            :: styled
            @ [ style_chunk syntax_style (inherited @ [ "markup.italic" ]) "*" ]
      | Parser.Strong values ->
          let styled = inline_chunks syntax_style ~conceal (inherited @ [ "markup.strong" ]) values in
          if conceal then styled
          else
            style_chunk syntax_style (inherited @ [ "markup.strong" ]) "**"
            :: styled
            @ [ style_chunk syntax_style (inherited @ [ "markup.strong" ]) "**" ]
      | Parser.Delete values ->
          let styled = inline_chunks syntax_style ~conceal (inherited @ [ "markup.strikethrough" ]) values in
          if conceal then styled
          else
            style_chunk syntax_style (inherited @ [ "markup.strikethrough" ]) "~~"
            :: styled
            @ [ style_chunk syntax_style (inherited @ [ "markup.strikethrough" ]) "~~" ]
      | Parser.Code_span text ->
          let styled = [ style_chunk syntax_style (inherited @ [ "markup.raw" ]) text ] in
          if conceal then styled
          else
            style_chunk syntax_style (inherited @ [ "markup.raw" ]) "`"
            :: styled
            @ [ style_chunk syntax_style (inherited @ [ "markup.raw" ]) "`" ]
      | Parser.Link { label; href } ->
          let styled =
            inline_chunks syntax_style ~conceal (inherited @ [ "markup.link.label" ]) label
            |> List.map (fun (chunk : Lib.Styled_text.chunk) ->
                   Styled.chunk chunk.text ?fg:chunk.fg ?bg:chunk.bg
                     ~attributes:chunk.attributes ~link:href)
          in
          if conceal then styled
          else
            style_chunk syntax_style inherited "["
            :: styled
            @ [ style_chunk syntax_style inherited "](";
                style_chunk ~link:href syntax_style [ "markup.link.url" ] href;
                style_chunk syntax_style inherited ")" ]
      | Parser.Image { alt; href } ->
          let styled = [ style_chunk ~link:href syntax_style [ "markup.link.label" ] alt ] in
          if conceal then styled
          else
            style_chunk syntax_style [ "markup.link.label" ] "!["
            :: styled
            @ [ style_chunk syntax_style [ "markup.link.label" ] "](";
                style_chunk ~link:href syntax_style [ "markup.link.url" ] href;
                style_chunk syntax_style [ "markup.link.label" ] ")" ]
      | Parser.Hard_break -> [ style_chunk syntax_style inherited "\n" ])
    values

let styled_inline markdown names values =
  let value = Styled.create (inline_chunks markdown.syntax_style ~conceal:markdown.conceal names values) in
  let value =
    let content = Styled.plain_text value in
    Detect_links.apply ~content ~styled_text:value
      (Detect_links.ranges ~content ~highlights:[])
  in
  Styled.map
    (fun chunk ->
      {
        chunk with
        fg = (match chunk.fg, markdown.fg with None, Some color -> Some color | value, _ -> value);
        bg = (match chunk.bg, markdown.bg with None, Some color -> Some color | value, _ -> value);
      })
    value

let inline_text_block markdown ?id names values =
  Text.create markdown.context ?id ~wrap_mode:markdown.wrap_mode
    ~content:(styled_inline markdown names values) ()

let rendered_text text =
  {
    renderable = Text.as_renderable text;
    selected_text = (fun () -> Text.selected_text text);
  }

let map_text result = Result.map rendered_text result

let table_alignment = function
  | Parser.Align_left -> Text_table.Left
  | Parser.Align_center -> Text_table.Center
  | Parser.Align_right -> Text_table.Right
  | Parser.Align_default -> Text_table.Default

let render_token markdown token index =
  let id = Printf.sprintf "markdown-block-%d" index in
  match token with
  | Parser.Heading { level; inlines; _ } ->
      inline_text_block markdown ~id [ "markup.heading"; "markup.heading." ^ string_of_int level ] inlines
      |> map_text
  | Parser.Paragraph { inlines; _ } ->
      inline_text_block markdown ~id [] inlines |> map_text
  | Parser.Code_block { language; text; _ } ->
      Code.create markdown.context ~id ~content:text ?filetype:language
        ?tree_sitter_client:markdown.tree_sitter_client
        ?background:markdown.background
        ~syntax_style:markdown.syntax_style ~conceal:markdown.conceal_code
        ~draw_unstyled_text:(not markdown.streaming)
        ~streaming:markdown.streaming ~wrap_mode:markdown.wrap_mode ()
      |> Result.map (fun code ->
             (* Unhighlighted fences render through the text buffer, so carry
                the documented default fg/bg into it; otherwise unstyled code
                falls back to the renderer's native default color. *)
             (match markdown.fg with
             | Some color ->
                 ignore
                   (Text_buffer_renderable.set_default_fg
                      (Code.text_buffer_renderable code) (Some color))
             | None -> ());
             (match markdown.bg with
             | Some color ->
                 ignore
                   (Text_buffer_renderable.set_default_bg
                      (Code.text_buffer_renderable code) (Some color))
             | None -> ());
             {
               renderable = Code.as_renderable code;
               selected_text = (fun () -> Code.selected_text code);
             })
  | Parser.Blockquote { inlines; _ } ->
      Result.bind
        (Box.create markdown.context ~id ~border:Box.all_borders
           ~border_color:(Option.value markdown.fg ~default:Color.white)
           ~should_fill:false ())
        (fun box ->
          Result.bind (inline_text_block markdown ~id:(id ^ "-text") [ "markup.quote" ] inlines)
            (fun text ->
              Result.bind
                (Layout_children.add (Layout_children.Private.of_renderable (Box.as_renderable box))
                   (Text.as_renderable text))
                (fun _ ->
                  Ok
                    {
                      renderable = Box.as_renderable box;
                      selected_text = (fun () -> Text.selected_text text);
                    })))
  | Parser.Unordered_list { items; _ } ->
      let chunks =
        List.concat
          (List.mapi
          (fun index item ->
            let marker = style_chunk markdown.syntax_style [ "punctuation.special" ] "• " in
            [ marker ] @ inline_chunks markdown.syntax_style ~conceal:markdown.conceal [] item.Parser.inlines
             @ (if index < List.length items - 1 then [ Styled.chunk "\n" ] else []))
          items)
      in
      Text.create markdown.context ~id ~wrap_mode:markdown.wrap_mode ~content:(Styled.create chunks) ()
      |> map_text
  | Parser.Ordered_list { start; items; _ } ->
      let chunks =
        List.concat
          (List.mapi
          (fun index item ->
            let marker = style_chunk markdown.syntax_style [ "punctuation.special" ] (string_of_int (start + index) ^ ". ") in
            [ marker ] @ inline_chunks markdown.syntax_style ~conceal:markdown.conceal [] item.Parser.inlines
             @ (if index < List.length items - 1 then [ Styled.chunk "\n" ] else []))
          items)
      in
      Text.create markdown.context ~id ~wrap_mode:markdown.wrap_mode ~content:(Styled.create chunks) ()
      |> map_text
  | Parser.Table { headers; rows; alignments; _ } ->
      let cells values =
        List.map
          (fun value ->
            Text_table.Styled
              (Styled.create
                 (inline_chunks markdown.syntax_style ~conceal:markdown.conceal [] value)))
          values
      in
      let table_content = cells headers :: List.map cells rows in
      Text_table.create markdown.context ~id ~content:table_content
        ~column_alignments:(List.map table_alignment alignments)
        ~wrap_mode:markdown.wrap_mode ~show_borders:markdown.table_options.show_borders
        ~outer_border:markdown.table_options.outer_border
        ~cell_padding_x:markdown.table_options.cell_padding_x
        ~cell_padding_y:markdown.table_options.cell_padding_y
        ?fg:markdown.fg ?bg:markdown.bg ?border_color:markdown.fg ()
      |> Result.map (fun table ->
             {
               renderable = Text_table.as_renderable table;
               selected_text = (fun () -> Text_table.selected_text table);
             })
  | Parser.Horizontal_rule _ ->
      Text.create markdown.context ~id ~content:(Styled.of_string "────────────────") ()
      |> map_text
  | Parser.Html raw ->
      Text.create markdown.context ~id ~content:(Styled.of_string raw) ()
      |> map_text

let clear_blocks markdown =
  let destroy_block (block : block_entry) =
    ignore (Layout_children.remove markdown.children block.renderable);
    Renderable.destroy_recursively block.renderable
  in
  List.iter destroy_block markdown.blocks;
  markdown.blocks <- []

let clear_blocks_from markdown keep_count =
  let rec split index kept removed = function
    | [] -> List.rev kept, List.rev removed
    | block :: rest when index < keep_count ->
        split (index + 1) (block :: kept) removed rest
    | block :: rest -> split (index + 1) kept (block :: removed) rest
  in
  let kept, removed = split 0 [] [] markdown.blocks in
  List.iter
    (fun (block : block_entry) ->
      ignore (Layout_children.remove markdown.children block.renderable);
      Renderable.destroy_recursively block.renderable)
    removed;
  markdown.blocks <- kept

let rec prefix_length old_tokens new_tokens limit index =
  if index >= limit then index
  else
    match old_tokens, new_tokens with
    | old :: old_tail, new_ :: new_tail
      when String.equal (Parser.token_raw old.token) (Parser.token_raw new_) ->
        prefix_length old_tail new_tail limit (index + 1)
    | _ -> index

let rebuild ?(reuse = false) markdown =
  let new_tokens = Parser.tokens markdown.parse_state in
  let reusable_count =
    if reuse then
      prefix_length markdown.blocks new_tokens
        (min (Parser.stable_token_count markdown.parse_state)
           (min (List.length markdown.blocks) (List.length new_tokens)))
        0
    else 0
  in
  let old_prefix =
    let rec take count values result =
      if count <= 0 then List.rev result
      else
        match values with
        | [] -> List.rev result
        | value :: rest -> take (count - 1) rest (value :: result)
    in
    take reusable_count markdown.blocks []
  in
  clear_blocks_from markdown reusable_count;
  let rendered = ref (List.rev old_prefix) in
  let failure = ref None in
  List.iteri
    (fun index token ->
      if index >= reusable_count then
        match !failure with
        | Some _ -> ()
        | None ->
            (match render_token markdown token index with
            | Error error -> failure := Some error
            | Ok rendered_block ->
                (match Layout_children.add markdown.children rendered_block.renderable with
                | Error error ->
                    Renderable.destroy_recursively rendered_block.renderable;
                    failure := Some error
                | Ok _ ->
                    rendered :=
                      {
                        token;
                        renderable = rendered_block.renderable;
                        selected_text = rendered_block.selected_text;
                      }
                      :: !rendered))
    ) new_tokens;
  match !failure with
  | Some error -> clear_blocks markdown; Error error
  | None -> markdown.blocks <- List.rev !rendered; Renderable.request_render markdown.renderable

let create context ?id ?(content = "") ?syntax_style ?fg ?bg
    ?tree_sitter_client ?background ?(conceal = true) ?(conceal_code = false)
    ?(streaming = false) ?(wrap_mode = Text_buffer_view.Word) ?table_options () =
  let syntax_style, owns_syntax_style = match syntax_style with Some value -> value, false | None -> Syntax_style.create (), true in
  let table_options = Option.value table_options ~default:{ show_borders = true; outer_border = true; cell_padding_x = 1; cell_padding_y = 0 } in
  match Renderable.Private.create context ?id () with
  | Error error -> if owns_syntax_style then Syntax_style.destroy syntax_style; Error error
  | Ok renderable ->
      let markdown =
        { renderable; children = Layout_children.Private.of_renderable renderable; context; content; syntax_style; owns_syntax_style; fg; bg; tree_sitter_client; background; conceal; conceal_code; streaming; wrap_mode; table_options; parse_state = Parser.parse content; blocks = []; destroyed = false }
      in
      register_default_styles syntax_style;
      let result = Result.bind (Renderable.set_flex_direction renderable Yoga.Flex_column) (fun () -> rebuild markdown) in
      match result with
      | Ok () -> Ok markdown
      | Error error -> Renderable.destroy renderable; if owns_syntax_style then Syntax_style.destroy syntax_style; Error error

let set_content markdown value =
  match ensure_alive markdown with
  | Error error -> Error error
  | Ok () ->
      markdown.content <- value;
      markdown.parse_state <-
        Parser.parse_incremental
          ~trailing_unstable:(if markdown.streaming then 2 else 0)
          value (Some markdown.parse_state);
      rebuild ~reuse:true markdown

let set_syntax_style markdown value =
  match ensure_alive markdown with
  | Error error -> Error error
  | Ok () -> markdown.syntax_style <- value; rebuild markdown

let set_conceal markdown value =
  match ensure_alive markdown with
  | Error error -> Error error
  | Ok () -> markdown.conceal <- value; rebuild markdown

let set_conceal_code markdown value =
  match ensure_alive markdown with
  | Error error -> Error error
  | Ok () -> markdown.conceal_code <- value; rebuild markdown

let selected_text markdown =
  match ensure_alive markdown with
  | Error error -> Error error
  | Ok () ->
      let selected = ref [] in
      let failure = ref None in
      List.iter
        (fun (block : block_entry) ->
          match !failure with
          | Some _ -> ()
          | None ->
              (match block.selected_text () with
              | Error error -> failure := Some error
              | Ok value when String.length value = 0 -> ()
              | Ok value -> selected := value :: !selected))
        markdown.blocks;
      (match !failure with
      | Some error -> Error error
      | None -> Ok (String.concat "\n" (List.rev !selected)))

let streaming markdown = markdown.streaming

let set_streaming markdown value =
  match ensure_alive markdown with
  | Error error -> Error error
  | Ok () when Bool.equal markdown.streaming value -> Ok ()
  | Ok () ->
      markdown.streaming <- value;
      markdown.parse_state <-
        Parser.parse_incremental
          ~trailing_unstable:(if value then 2 else 0)
          markdown.content (Some markdown.parse_state);
      rebuild ~reuse:true markdown

let destroy markdown =
  if not markdown.destroyed then begin
    markdown.destroyed <- true;
    clear_blocks markdown;
    Renderable.destroy markdown.renderable;
    if markdown.owns_syntax_style then Syntax_style.destroy markdown.syntax_style
  end
