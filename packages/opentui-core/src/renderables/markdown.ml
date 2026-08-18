module Parser = Markdown_parser
module Styled = Lib.Styled_text

type table_options = {
  show_borders : bool;
  outer_border : bool;
  cell_padding_x : int;
  cell_padding_y : int;
  column_width_mode : Text_table.column_width_mode;
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
      ("markup.list", definition ~fg:green ());
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
  Result.bind
    (Text.create markdown.context ?id ~wrap_mode:markdown.wrap_mode
       ~content:(styled_inline markdown names values) ())
    (fun text ->
      match
        Renderable.set_width (Text.as_renderable text) (Yoga.Percent 100.0)
      with
      | Ok () -> Ok text
      | Error error ->
          Text.destroy text;
          Error error)

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

let rec render_token markdown token id =
  match token with
  | Parser.Heading { level; inlines; _ } ->
      inline_text_block markdown ~id [ "markup.heading"; "markup.heading." ^ string_of_int level ] inlines
      |> map_text
  | Parser.Paragraph { inlines; _ } ->
      inline_text_block markdown ~id [] inlines |> map_text
  | Parser.Code_block { language; text; _ } ->
      Result.bind
        (Code.create markdown.context ~id ~content:text ?filetype:language
           ?tree_sitter_client:markdown.tree_sitter_client
           ?background:markdown.background
           ~syntax_style:markdown.syntax_style ~conceal:markdown.conceal_code
           ~draw_unstyled_text:(not markdown.streaming)
           ~streaming:markdown.streaming ~wrap_mode:markdown.wrap_mode ())
        (fun code ->
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
          (match
             Renderable.set_width (Code.as_renderable code) (Yoga.Percent 100.0)
           with
          | Ok () ->
              Ok
                {
                  renderable = Code.as_renderable code;
                  selected_text = (fun () -> Code.selected_text code);
                }
          | Error error ->
              Code.destroy code;
              Error error))
  | Parser.Blockquote { inlines; _ } ->
      Result.bind
        (Box.create markdown.context ~id
           ~border:(Lib.Border.Sides [ Lib.Border.Left ])
           ~border_color:(Option.value markdown.fg ~default:Color.white)
           ~should_fill:false ())
        (fun box ->
          Result.bind
            (Renderable.set_width (Box.as_renderable box) (Yoga.Percent 100.0))
            (fun () ->
              Result.bind
                (Renderable.set_flex_shrink (Box.as_renderable box) (Some 0.0))
                (fun () ->
                  Result.bind
                (Renderable.set_padding (Box.as_renderable box)
                   ~edge:Yoga.Left (Yoga.Point 1.0))
                    (fun () ->
                      Result.bind
                        (inline_text_block markdown ~id:(id ^ "-text") [ "markup.quote" ] inlines)
                        (fun text ->
                          Result.bind
                            (Layout_children.add (Box.children box) (Text.as_renderable text))
                            (fun _ ->
                              Ok
                                {
                                  renderable = Box.as_renderable box;
                                  selected_text = (fun () -> Text.selected_text text);
                                }))))))
  | Parser.Unordered_list { items; _ } ->
      render_list markdown ~id ~ordered:false ~start:1 items
  | Parser.Ordered_list { start; items; _ } ->
      render_list markdown ~id ~ordered:true ~start items
  | Parser.Table { headers; rows; alignments; _ } ->
      let cells values =
        List.map
          (fun value ->
            Text_table.Styled
              (styled_inline markdown [] value))
          values
      in
      let table_content = cells headers :: List.map cells rows in
      (match
         Text_table.create markdown.context ~id ~content:table_content
           ~column_alignments:(List.map table_alignment alignments)
           ~wrap_mode:markdown.wrap_mode
           ~column_width_mode:markdown.table_options.column_width_mode
           ~show_borders:markdown.table_options.show_borders
           ~outer_border:markdown.table_options.outer_border
           ~cell_padding_x:markdown.table_options.cell_padding_x
           ~cell_padding_y:markdown.table_options.cell_padding_y
           ?fg:markdown.fg ?bg:markdown.bg ?border_color:markdown.fg ()
       with
       | Error error -> Error error
       | Ok table ->
           (match
              Renderable.set_width (Text_table.as_renderable table)
                (Yoga.Percent 100.0)
            with
            | Ok () ->
                Ok
                  {
                    renderable = Text_table.as_renderable table;
                    selected_text = (fun () -> Text_table.selected_text table);
                  }
            | Error error ->
                Text_table.destroy table;
                Error error))
  | Parser.Horizontal_rule _ ->
      inline_text_block markdown ~id [] [ Parser.Text "────────────────" ]
      |> map_text
  | Parser.Html raw ->
      inline_text_block markdown ~id [] [ Parser.Text raw ] |> map_text

and render_list markdown ~id ~ordered ~start items =
  let marker_display_width marker =
    Lib.Text_metrics.display_width Lib.Text_metrics.Wcwidth marker
  in
  let has_trailing_blank_line raw =
    match List.rev (String.split_on_char '\n' raw) with
    | last :: _ -> String.length (String.trim last) = 0
    | [] -> false
  in
  let marker_width =
    if ordered then
      List.fold_left
        (fun width (index, _) ->
          let marker = string_of_int (start + index) ^ "." in
          Int.max width (marker_display_width marker))
        1 (List.mapi (fun index item -> index, item) items)
    else 1
  in
  Result.bind
    (Box.create markdown.context ~id ~should_fill:false ())
    (fun list_box ->
      let configure result operation = Result.bind result (fun () -> operation ()) in
      let result =
        configure (Renderable.set_width (Box.as_renderable list_box) (Yoga.Percent 100.0))
          (fun () -> Renderable.set_flex_direction (Box.as_renderable list_box) Yoga.Flex_column)
      in
      let result =
        configure result (fun () -> Renderable.set_flex_shrink (Box.as_renderable list_box) (Some 0.0))
      in
      let selections = ref [] in
      let add_item index item result =
        Result.bind result (fun () ->
            let marker = if ordered then string_of_int (start + index) ^ "." else "•" in
            let marker_text =
              String.make (marker_width - marker_display_width marker) ' ' ^ marker ^ " "
            in
            Result.bind
              (Box.create markdown.context ~id:(id ^ "-item-" ^ string_of_int index)
                 ~should_fill:false ())
              (fun row ->
                let row_renderable = Box.as_renderable row in
                let body_id = id ^ "-item-" ^ string_of_int index ^ "-body" in
                let marker_id = id ^ "-item-" ^ string_of_int index ^ "-marker" in
                let result =
                  configure (Renderable.set_width row_renderable (Yoga.Percent 100.0))
                    (fun () -> Renderable.set_flex_direction row_renderable Yoga.Flex_row)
                in
                let result =
                  configure result (fun () -> Renderable.set_flex_shrink row_renderable (Some 0.0))
                in
                let result =
                  configure result (fun () ->
                      if has_trailing_blank_line item.Parser.raw then
                        Renderable.set_margin row_renderable ~edge:Yoga.Bottom
                          (Yoga.Point 1.0)
                      else Ok ())
                in
                Result.bind result (fun () ->
                    Result.bind
                      (Text.create markdown.context ~id:marker_id
                          ~content:
                           (Styled.create
                              [ style_chunk markdown.syntax_style [ "markup.list" ] marker_text ])
                         ())
                      (fun marker_text_renderable ->
                        let marker_renderable = Text.as_renderable marker_text_renderable in
                        let result =
                          configure
                            (Renderable.set_width marker_renderable
                               (Yoga.Point (float_of_int (marker_width + 1))))
                            (fun () -> Renderable.set_flex_shrink marker_renderable (Some 0.0))
                        in
                        Result.bind result (fun () ->
                            Result.bind
                              (Box.create markdown.context ~id:body_id ~should_fill:false ())
                              (fun body ->
                                let body_renderable = Box.as_renderable body in
                                let result =
                                  configure
                                    (Renderable.set_flex_direction body_renderable Yoga.Flex_column)
                                    (fun () -> Renderable.set_flex_grow body_renderable (Some 1.0))
                                in
                                let result =
                                  configure result
                                    (fun () -> Renderable.set_flex_shrink body_renderable (Some 1.0))
                                in
                                Result.bind result (fun () ->
                                    Result.bind
                                      (Layout_children.add (Box.children row) marker_renderable)
                                      (fun _ ->
                                        Result.bind
                                          (inline_text_block markdown
                                             ~id:(body_id ^ "-text") [] item.Parser.inlines)
                                          (fun text ->
                                            selections := (fun () -> Text.selected_text text) :: !selections;
                                            Result.bind
                                              (Layout_children.add (Box.children body)
                                                 (Text.as_renderable text))
                                              (fun _ ->
                                                let add_child child_index child result =
                                                  Result.bind result (fun () ->
                                                      Result.bind
                                                        (render_token markdown child
                                                           (body_id ^ "-child-"
                                                          ^ string_of_int child_index))
                                                        (fun rendered ->
                                                          selections := rendered.selected_text :: !selections;
                                                          Result.map
                                                            (fun _ -> ())
                                                            (Layout_children.add
                                                               (Box.children body)
                                                               rendered.renderable)))
                                                in
                                                let children_result =
                                                  List.mapi (fun child_index child -> child_index, child)
                                                    item.Parser.children
                                                  |> List.fold_left
                                                       (fun result (child_index, child) ->
                                                         add_child child_index child result)
                                                       (Ok ())
                                                in
                                                Result.bind children_result (fun () ->
                                                    Result.bind
                                                      (Layout_children.add
                                                         (Box.children row) body_renderable)
                                                      (fun _ ->
                                                        Result.map
                                                          (fun _ -> ())
                                                          (Layout_children.add
                                                             (Box.children list_box)
                                                             row_renderable)))))))))))))
      in
      let result =
        List.mapi (fun index item -> index, item) items
        |> List.fold_left (fun result (index, item) -> add_item index item result) result
      in
      match result with
      | Error error ->
          Box.destroy_recursively list_box;
          Error error
      | Ok () ->
          Ok
            {
              renderable = Box.as_renderable list_box;
              selected_text = (fun () ->
                let values = ref [] in
                let failure = ref None in
                List.iter
                  (fun selected ->
                    match !failure with
                    | Some _ -> ()
                    | None ->
                        (match selected () with
                        | Error error -> failure := Some error
                        | Ok value when String.length value = 0 -> ()
                        | Ok value -> values := value :: !values))
                  (List.rev !selections);
                match !failure with
                | Some error -> Error error
                | None -> Ok (String.concat "\n" (List.rev !values)));
            })

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
            (match render_token markdown token
               (Printf.sprintf "markdown-block-%d" index) with
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
  let table_options =
    Option.value table_options
      ~default:
        {
          show_borders = true;
          outer_border = true;
          cell_padding_x = 1;
          cell_padding_y = 0;
          column_width_mode = Text_table.Full;
        }
  in
  match Renderable.Private.create context ?id () with
  | Error error -> if owns_syntax_style then Syntax_style.destroy syntax_style; Error error
  | Ok renderable ->
      let markdown =
        { renderable; children = Layout_children.Private.of_renderable renderable; context; content; syntax_style; owns_syntax_style; fg; bg; tree_sitter_client; background; conceal; conceal_code; streaming; wrap_mode; table_options; parse_state = Parser.parse content; blocks = []; destroyed = false }
      in
      register_default_styles syntax_style;
      let result =
        Result.bind
          (Renderable.set_flex_direction renderable Yoga.Flex_column)
          (fun () ->
            Result.bind
              (Renderable.set_flex_shrink renderable (Some 0.0))
              (fun () -> rebuild markdown))
      in
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
      (* Streaming changes the visibility policy of every fenced Code child;
         reusing the old block tree would leave those children with the
         previous [draw_unstyled_text] and [streaming] settings. *)
      rebuild markdown

let destroy markdown =
  if not markdown.destroyed then begin
    markdown.destroyed <- true;
    clear_blocks markdown;
    Renderable.destroy markdown.renderable;
    if markdown.owns_syntax_style then Syntax_style.destroy markdown.syntax_style
  end
