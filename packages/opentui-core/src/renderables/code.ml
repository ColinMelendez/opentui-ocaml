module Types = Lib.Tree_sitter_types
module Styled = Lib.Styled_text
module Background = Platform.Eio_runtime.Background

type highlight_state = Idle | Pending | Applied | Fallback of Types.parser_error

type highlight_context = {
  content : string;
  filetype : string;
  syntax_style : Syntax_style.t;
}

type chunks_context = {
  content : string;
  filetype : string;
  syntax_style : Syntax_style.t;
  highlights : Types.highlight list;
}

type settlement = {
  promise : unit Eio.Promise.t;
  resolver : unit Eio.Promise.u;
}

type request =
  | Plain of {
      generation : int;
      content : string;
    }
  | Fallback of {
      generation : int;
      content : string;
      error : Types.parser_error;
    }
  | Highlight of {
      generation : int;
      content : string;
      parser : Types.parser;
    }

type request_start_error =
  | Admission_error of Error.t
  | Application_error of Error.t

type t = {
  text_buffer_renderable : Text_buffer_renderable.t;
  mutable content : string;
  mutable filetype : string option;
  mutable syntax_style : Syntax_style.t;
  mutable owns_syntax_style : bool;
  mutable tree_sitter_client : Lib.Tree_sitter_client.t option;
  background : Background.submitter option;
  mutable conceal : bool;
  mutable draw_unstyled_text : bool;
  mutable streaming : bool;
  initial_styled_text : Styled.t option;
  mutable base_highlight : string option;
  on_highlight :
    (Types.highlight list ->
    highlight_context ->
    (Types.highlight list, Types.parser_error) result)
    option;
  on_chunks :
    (Styled.t -> chunks_context -> (Styled.t, Types.parser_error) result)
    option;
  mutable highlights : Types.highlight list;
  mutable line_sources : int array option;
  mutable state : highlight_state;
  mutable settled_state : highlight_state;
  mutable generation : int;
  mutable running : Background.job option;
  mutable pending : request option;
  mutable settlement : settlement;
  mutable has_settled_rendered_content : bool;
  mutable destroyed : bool;
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

let make_settlement () =
  let promise, resolver = Eio.Promise.create () in
  { promise; resolver }

let resolve_settlement settlement =
  ignore (Eio.Promise.try_resolve settlement.resolver ())

let replace_settlement code =
  resolve_settlement code.settlement;
  code.settlement <- make_settlement ()

let settle code state =
  code.state <- state;
  code.settled_state <- state;
  resolve_settlement code.settlement

let ensure_alive code =
  if code.destroyed || Renderable.is_destroyed (as_renderable code) then
    Error Error.Destroyed
  else Ok ()

let is_current code generation =
  not code.destroyed
  && not (Renderable.is_destroyed (as_renderable code))
  && Int.equal generation code.generation

let fallback_content code ~content =
  match code.initial_styled_text with
  | Some initial when code.draw_unstyled_text && not (String.equal content "") -> initial
  | Some _ | None -> Styled.of_string content

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
  if not (is_current code generation) then Ok ()
  else
    match Text_buffer_renderable.set_styled_text code.text_buffer_renderable styled with
    | Error error -> Error error
    | Ok () ->
        code.has_settled_rendered_content <- true;
        ignore (Renderable.request_render (as_renderable code));
        Ok ()

let apply_fallback code ~generation ~content error =
  if not (is_current code generation) then Ok ()
  else
    match apply_content code ~generation (fallback_content code ~content) with
    | Error application_error -> Error application_error
    | Ok () ->
        code.highlights <- [];
        code.line_sources <- None;
        settle code (Fallback error);
        Ok ()

let apply_plain code ~generation ~content =
  if not (is_current code generation) then Ok ()
  else
    match apply_content code ~generation (fallback_content code ~content) with
    | Error application_error -> Error application_error
    | Ok () ->
        code.highlights <- [];
        code.line_sources <- None;
        settle code Idle;
        Ok ()

let apply_highlights code ~generation ~content ~filetype highlights =
  if not (is_current code generation) then Ok ()
  else
    let apply_chunks highlights styled =
      if not (is_current code generation) then Ok ()
      else
        let line_sources =
          Tree_sitter_styled_text.concealed_line_sources
            ~content ~highlights ~conceal:code.conceal
        in
        match apply_content code ~generation styled with
        | Error application_error -> Error application_error
        | Ok () ->
            code.highlights <- highlights;
            code.line_sources <- line_sources;
            settle code Applied;
            Ok ()
    in
    let convert highlights =
      Tree_sitter_styled_text.tree_sitter_to_styled_text
        ~syntax_style:code.syntax_style ?base_highlight:code.base_highlight
        ~conceal:code.conceal ~content ~highlights ()
    in
    let apply_converted highlights styled =
      match code.on_chunks with
      | None -> apply_chunks highlights styled
      | Some callback ->
          let context =
            {
              content;
              filetype;
              syntax_style = code.syntax_style;
              highlights;
            }
          in
          (match callback styled context with
          | Error error ->
              if is_current code generation then
                apply_fallback code ~generation ~content error
              else Ok ()
          | Ok styled ->
              if not (is_current code generation) then Ok ()
              else apply_chunks highlights styled)
    in
    match code.on_highlight with
    | None -> apply_converted highlights (convert highlights)
    | Some callback ->
        let context =
          {
            content;
            filetype;
            syntax_style = code.syntax_style;
          }
        in
        (match callback highlights context with
        | Error error ->
            if is_current code generation then
              apply_fallback code ~generation ~content error
            else Ok ()
        | Ok highlights ->
            if not (is_current code generation) then Ok ()
            else apply_converted highlights (convert highlights))

let background_error = function
  | Background.Closed -> Error.Closed
  | Background.Wrong_domain -> Error.Wrong_domain
  | Background.Invalid_worker_count count ->
      ignore count;
      Error.Invalid_argument

let owned_string value = String.sub value 0 (String.length value)

let clear_unsettled_content code =
  code.has_settled_rendered_content <- false;
  Result.bind
    (Text_buffer_renderable.clear code.text_buffer_renderable)
    (fun () -> Renderable.request_render (as_renderable code))

let show_unstyled_content code =
  code.has_settled_rendered_content <- false;
  let styled =
    match code.initial_styled_text with
    | Some initial when not (String.equal code.content "") -> initial
    | Some _ | None -> Styled.of_string code.content
  in
  Result.bind
    (Text_buffer_renderable.set_styled_text code.text_buffer_renderable styled)
    (fun () -> Renderable.request_render (as_renderable code))

let prepare_highlight_visibility code =
  if code.streaming && code.has_settled_rendered_content then Ok ()
  else if code.draw_unstyled_text then show_unstyled_content code
  else clear_unsettled_content code

let cleanup code =
  if not code.destroyed then begin
    code.destroyed <- true;
    code.pending <- None;
    Option.iter Background.cancel code.running;
    code.running <- None;
    resolve_settlement code.settlement;
    if code.owns_syntax_style then begin
      code.owns_syntax_style <- false;
      Syntax_style.destroy code.syntax_style
    end
  end

let request_generation = function
  | Plain { generation; content } ->
      ignore content;
      generation
  | Fallback { generation; content; error } ->
      ignore content;
      ignore error;
      generation
  | Highlight { generation; content; parser } ->
      ignore content;
      ignore parser;
      generation

let run_request_on_owner code request =
  if not (is_current code (request_generation request)) then Ok ()
  else
    match request with
    | Plain { generation; content } -> apply_plain code ~generation ~content
    | Fallback { generation; content; error } ->
        apply_fallback code ~generation ~content error
    | Highlight { generation; content; parser } ->
        let filetype =
          match code.filetype with
          | Some value -> value
          | None -> parser.Types.filetype
        in
        (match Lib.Tree_sitter_client.run_parser parser ~content with
        | Error error -> apply_fallback code ~generation ~content error
        | Ok highlights ->
            apply_highlights code ~generation ~content ~filetype highlights)

let settle_after_application_error code request application_error =
  ignore application_error;
  if is_current code (request_generation request) then begin
    code.state <- code.settled_state;
    resolve_settlement code.settlement
  end

let abort_inflight code =
  if not code.destroyed then begin
    code.pending <- None;
    code.state <- code.settled_state;
    resolve_settlement code.settlement
  end

let rec start_pending code =
  if code.destroyed || Option.is_some code.running then ()
  else
    match code.pending with
    | None -> ()
    | Some request ->
        code.pending <- None;
        let completed = ref false in
        Fun.protect
          ~finally:(fun () -> if not !completed then abort_inflight code)
          (fun () ->
            match start_request code request with
            | Ok () -> completed := true
            | Error (Admission_error _) ->
                (match run_request_on_owner code request with
                | Ok () -> completed := true
                | Error application_error ->
                    settle_after_application_error code request application_error;
                    completed := true)
            | Error (Application_error application_error) ->
                settle_after_application_error code request application_error;
                completed := true)

and finish_request code request result =
  code.running <- None;
  let completed = ref false in
  Fun.protect
    ~finally:(fun () -> if not !completed then abort_inflight code)
    (fun () ->
      let application_result =
        match request with
        | Plain { generation; content } -> apply_plain code ~generation ~content
        | Fallback { generation; content; error } ->
            apply_fallback code ~generation ~content error
        | Highlight { generation; content; parser } ->
            let filetype =
              match code.filetype with
              | Some value -> value
              | None -> parser.Types.filetype
            in
            (match result with
            | Error error -> apply_fallback code ~generation ~content error
            | Ok highlights ->
                apply_highlights code ~generation ~content ~filetype highlights)
      in
      (match application_result with
      | Ok () -> ()
      | Error application_error ->
          settle_after_application_error code request application_error);
      completed := true;
      start_pending code)

and start_request code request =
  if not (is_current code (request_generation request)) then Ok ()
  else
    match request with
    | Highlight { generation; content; parser } ->
        (match parser.Types.worker_safety, code.background with
        | Types.Worker_safe, Some submitter ->
            let owned_content = owned_string content in
            let work () =
              Lib.Tree_sitter_client.run_parser parser ~content:owned_content
            in
            let on_complete result = finish_request code request result in
            (match Background.submit submitter ~work ~on_complete with
            | Ok job ->
                code.running <- Some job;
                if is_current code generation then code.state <- Pending;
                Ok ()
            | Error error -> Error (Admission_error (background_error error)))
        | Types.Owner_only, _ | Types.Worker_safe, None ->
            Result.map_error
              (fun error -> Application_error error)
              (run_request_on_owner code request))
    | Plain { generation; content } ->
        ignore generation;
        ignore content;
        Result.map_error
          (fun error -> Application_error error)
          (run_request_on_owner code request)
    | Fallback { generation; content; error } ->
        ignore generation;
        ignore content;
        ignore error;
        Result.map_error
          (fun application_error -> Application_error application_error)
          (run_request_on_owner code request)

let request_for code ~generation =
  let content = owned_string code.content in
  if String.equal content "" then Plain { generation; content }
  else
    match code.filetype, code.tree_sitter_client with
    | Some filetype, Some client ->
        (match Lib.Tree_sitter_client.resolve_parser client filetype with
        | None -> Fallback { generation; content; error = Types.No_parser filetype }
        | Some parser -> Highlight { generation; content; parser })
    | Some filetype, None ->
        Fallback { generation; content; error = Types.No_parser filetype }
    | None, client ->
        ignore client;
        Plain { generation; content }

let refresh code =
  match ensure_alive code with
  | Error error -> Error error
  | Ok () ->
      code.generation <- code.generation + 1;
      let generation = code.generation in
      replace_settlement code;
      let request = request_for code ~generation in
      let retains_rendered_content =
        match request with
        | Highlight _ -> code.streaming && code.has_settled_rendered_content
        | Plain _ | Fallback _ -> false
      in
      if not retains_rendered_content then code.line_sources <- None;
      let visibility_result =
        match request with
        | Highlight _ -> prepare_highlight_visibility code
        | Plain _ | Fallback _ -> Ok ()
      in
      (match visibility_result with
      | Error error ->
          abort_inflight code;
          Error error
      | Ok () ->
          (match code.running, request with
          | Some _, Highlight _ ->
              code.pending <- Some request;
              code.state <- Pending;
              Ok ()
          | (Some _, (Plain _ | Fallback _)) | None, _ ->
              let completed = ref false in
              Fun.protect
                ~finally:(fun () -> if not !completed then abort_inflight code)
                (fun () ->
                  match start_request code request with
                  | Ok () ->
                      completed := true;
                      Ok ()
                  | Error (Admission_error error)
                  | Error (Application_error error) ->
                      abort_inflight code;
                      completed := true;
                      Error error)))

let create context ?id ?(content = "") ?filetype ?syntax_style
    ?tree_sitter_client ?background ?(wrap_mode = Text_buffer_view.Word)
    ?(conceal = true) ?(draw_unstyled_text = true) ?(streaming = false)
    ?initial_styled_text ?base_highlight ?on_highlight ?on_chunks () =
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
          background;
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
          settled_state = Idle;
          generation = 0;
          running = None;
          pending = None;
          settlement = make_settlement ();
          has_settled_rendered_content = false;
          destroyed = false;
        }
      in
      (match
         Renderable.once_destroyed (as_renderable code) (fun () -> cleanup code)
       with
      | Error error ->
          cleanup code;
          Text_buffer_renderable.destroy text_buffer_renderable;
          Error error
      | Ok subscription ->
          ignore subscription;
          (match refresh code with
          | Ok () -> Ok code
          | Error error ->
              Text_buffer_renderable.destroy text_buffer_renderable;
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
      let previous = code.syntax_style in
      let release_previous = code.owns_syntax_style && previous != value in
      code.syntax_style <- value;
      if release_previous then begin
        code.owns_syntax_style <- false;
        Syntax_style.destroy previous
      end;
      refresh code

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

let highlighting_done code = code.settlement.promise

let line_info code =
  map_line_info code
    (Text_buffer_renderable.line_info code.text_buffer_renderable)

let logical_line_info code =
  map_line_info code
    (Text_buffer_renderable.logical_line_info code.text_buffer_renderable)

let virtual_line_count code =
  Text_buffer_renderable.virtual_line_count code.text_buffer_renderable

let selected_text code =
  Text_buffer_renderable.selected_text code.text_buffer_renderable

let set_selection code ~start ~end_ () =
  Text_buffer_renderable.set_selection code.text_buffer_renderable ~start ~end_ ()

let set_wrap_mode code mode =
  Text_buffer_renderable.set_wrap_mode code.text_buffer_renderable mode

let wrap_mode code = Text_buffer_renderable.wrap_mode code.text_buffer_renderable
let scroll_x code = Text_buffer_renderable.scroll_x code.text_buffer_renderable
let scroll_y code = Text_buffer_renderable.scroll_y code.text_buffer_renderable

let set_scroll code ~x ~y =
  Text_buffer_renderable.set_scroll code.text_buffer_renderable ~x ~y

let destroy code =
  Renderable.destroy (as_renderable code)
