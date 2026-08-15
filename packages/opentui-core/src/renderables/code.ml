module Types = Lib.Tree_sitter_types
module Styled = Lib.Styled_text

type highlight_state = Idle | Applied | Fallback of Types.parser_error

type t = {
  text_buffer_renderable : Text_buffer_renderable.t;
  mutable content : string;
  mutable filetype : string option;
  mutable syntax_style : Syntax_style.t;
  mutable owns_syntax_style : bool;
  mutable tree_sitter_client : Lib.Tree_sitter_client.t option;
  mutable conceal : bool;
  mutable draw_unstyled_text : bool;
  mutable streaming : bool;
  initial_styled_text : Styled.t option;
  mutable base_highlight : string option;
  on_highlight : (Types.highlight list -> (Types.highlight list, Types.parser_error) result) option;
  on_chunks : (Styled.t -> (Styled.t, Types.parser_error) result) option;
  mutable highlights : Types.highlight list;
  mutable line_sources : int array option;
  mutable state : highlight_state;
  mutable generation : int;
}

let as_renderable code = Text_buffer_renderable.as_renderable code.text_buffer_renderable
let text_buffer_renderable code = code.text_buffer_renderable
let content code = code.content
let filetype code = code.filetype
let syntax_style code = code.syntax_style
let tree_sitter_client code = code.tree_sitter_client
let conceal code = code.conceal
let draw_unstyled_text code = code.draw_unstyled_text
let streaming code = code.streaming
let highlights code = code.highlights
let highlight_state code = code.state

let ensure_alive code =
  if Renderable.is_destroyed (as_renderable code) then Error Error.Destroyed else Ok ()

let fallback_content code =
  match code.initial_styled_text with
  | Some initial when code.draw_unstyled_text && not (String.equal code.content "") -> initial
  | Some _ | None -> Styled.of_string code.content

let map_line_info code result =
  Result.map
    (fun (info : Text_buffer_view.line_info) ->
      match code.line_sources with
      | None -> info
      | Some sources ->
          {
            info with
            line_sources =
              Array.map
                (fun source ->
                  if source >= 0 && source < Array.length sources then sources.(source)
                  else source)
                info.line_sources;
          })
    result

let apply_content code ~generation styled =
  if not (Int.equal generation code.generation) then
    Error Error.Destroyed
  else
    match Text_buffer_renderable.set_styled_text code.text_buffer_renderable styled with
    | Error error -> Error error
    | Ok () ->
        ignore (Renderable.request_render (as_renderable code));
        Ok ()

let refresh code =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () ->
      code.generation <- code.generation + 1;
      let generation = code.generation in
      code.line_sources <- None;
      let fallback error =
        code.highlights <- [];
        code.line_sources <- None;
        code.state <- Fallback error;
        apply_content code ~generation (fallback_content code)
      in
      if String.equal code.content "" then begin
        code.highlights <- [];
        code.state <- Idle;
        apply_content code ~generation (fallback_content code)
      end else
      match code.filetype, code.tree_sitter_client with
      | Some filetype, Some client ->
          let request =
            Lib.Tree_sitter_client.begin_request client ~content:code.content
              ~filetype
          in
          let highlights_result =
            Lib.Tree_sitter_client.highlight_request client request
          in
          (match highlights_result with
          | Error error -> fallback error
          | Ok highlights ->
              let apply_highlights highlights =
                if not (Int.equal generation code.generation) then
                  Error Error.Destroyed
                else begin
                  code.highlights <- highlights;
                  code.line_sources <-
                    Tree_sitter_styled_text.concealed_line_sources
                      ~content:code.content ~highlights ~conceal:code.conceal;
                  let styled =
                    Tree_sitter_styled_text.tree_sitter_to_styled_text
                      ~syntax_style:code.syntax_style
                      ?base_highlight:code.base_highlight
                      ~conceal:code.conceal ~content:code.content ~highlights ()
                  in
                  match code.on_chunks with
                  | None -> code.state <- Applied; apply_content code ~generation styled
                  | Some callback ->
                      (match callback styled with
                      | Error error -> fallback error
                      | Ok styled -> code.state <- Applied; apply_content code ~generation styled)
                end
              in
              (match code.on_highlight with
              | None -> apply_highlights highlights
              | Some callback ->
                  (match callback highlights with
                  | Error error -> fallback error
                  | Ok highlights -> apply_highlights highlights)))
      | Some filetype, None -> fallback (Types.No_parser filetype)
      | None, _ ->
          code.highlights <- [];
          code.line_sources <- None;
          code.state <- Idle;
          apply_content code ~generation (fallback_content code)

let create context ?id ?(content = "") ?filetype ?syntax_style
    ?tree_sitter_client ?(wrap_mode = Text_buffer_view.Word)
    ?(conceal = true) ?(draw_unstyled_text = true)
    ?(streaming = false) ?initial_styled_text ?base_highlight ?on_highlight
    ?on_chunks () =
  let syntax_style, owns_syntax_style =
    match syntax_style with
    | Some value -> value, false
    | None -> Syntax_style.create (), true
  in
  match
    Text_buffer_renderable.create context ?id ~wrap_mode
      ~selectable:true ~scrollable:true ()
  with
  | Error error ->
      if owns_syntax_style then Syntax_style.destroy syntax_style;
      Error error
  | Ok text_buffer_renderable ->
      let code =
        {
          text_buffer_renderable;
          content;
          filetype;
          syntax_style;
          owns_syntax_style;
          tree_sitter_client;
          conceal;
          draw_unstyled_text;
          streaming;
          initial_styled_text;
          base_highlight;
          on_highlight;
          on_chunks;
          highlights = [];
          line_sources = None;
          state = Idle;
          generation = 0;
        }
      in
      (match Text_buffer_renderable.set_syntax_style text_buffer_renderable
               (Some syntax_style) with
      | Error error ->
          Text_buffer_renderable.destroy text_buffer_renderable;
          if owns_syntax_style then Syntax_style.destroy syntax_style;
          Error error
      | Ok () ->
          (match refresh code with
          | Ok () -> Ok code
          | Error error ->
              Text_buffer_renderable.destroy text_buffer_renderable;
              if owns_syntax_style then Syntax_style.destroy syntax_style;
              Error error))

let set_content code value =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () -> code.content <- value; refresh code

let set_filetype code value =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () -> code.filetype <- value; refresh code

let set_syntax_style code value =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () ->
      (match Text_buffer_renderable.set_syntax_style code.text_buffer_renderable
               (Some value) with
      | Error error -> Error error
      | Ok () -> code.syntax_style <- value; refresh code)

let set_tree_sitter_client code value =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () -> code.tree_sitter_client <- value; refresh code

let set_conceal code value =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () -> code.conceal <- value; refresh code

let set_draw_unstyled_text code value =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () -> code.draw_unstyled_text <- value; refresh code

let set_streaming code value =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () when Bool.equal code.streaming value -> Ok ()
  | Ok () -> code.streaming <- value; refresh code

let line_info code = map_line_info code (Text_buffer_renderable.line_info code.text_buffer_renderable)
let logical_line_info code =
  map_line_info code (Text_buffer_renderable.logical_line_info code.text_buffer_renderable)
let virtual_line_count code = Text_buffer_renderable.virtual_line_count code.text_buffer_renderable
let selected_text code = Text_buffer_renderable.selected_text code.text_buffer_renderable

let set_selection code ~start ~end_ () =
  Text_buffer_renderable.set_selection code.text_buffer_renderable ~start ~end_ ()

let set_wrap_mode code mode = Text_buffer_renderable.set_wrap_mode code.text_buffer_renderable mode
let wrap_mode code = Text_buffer_renderable.wrap_mode code.text_buffer_renderable
let scroll_x code = Text_buffer_renderable.scroll_x code.text_buffer_renderable
let scroll_y code = Text_buffer_renderable.scroll_y code.text_buffer_renderable

let set_scroll code ~x ~y =
  Text_buffer_renderable.set_scroll code.text_buffer_renderable ~x ~y

let destroy code =
  if not (Renderable.is_destroyed (as_renderable code)) then begin
    Text_buffer_renderable.destroy code.text_buffer_renderable;
    if code.owns_syntax_style then Syntax_style.destroy code.syntax_style
  end
