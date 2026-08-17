module Parser = Diff_parser
module Styled = Lib.Styled_text

type view = Unified | Split

type side = { code : Code.t; line_number : Line_number.t }

type t = {
  renderable : Renderable.t;
  context : Render_context.t;
  mutable content : string;
  mutable view : view;
  filetype : string option;
  syntax_style : Syntax_style.t;
  owns_syntax_style : bool;
  tree_sitter_client : Lib.Tree_sitter_client.t option;
  background : Platform.Eio_runtime.Background.submitter option;
  mutable sync_scroll : bool;
  mutable show_line_numbers : bool;
  wrap_mode : Text_buffer_view.wrap_mode;
  mutable parsed : Parser.patch option;
  mutable parse_error : Parser.parse_error option;
  mutable left : side option;
  mutable right : side option;
  mutable error_text : Text.t option;
  mutable destroyed : bool;
}

let as_renderable diff = diff.renderable
let content diff = diff.content
let view diff = diff.view
let sync_scroll diff = diff.sync_scroll
let show_line_numbers diff = diff.show_line_numbers
let parse_error diff = diff.parse_error
let patch diff = diff.parsed
let left_code diff = Option.map (fun side -> side.code) diff.left
let right_code diff = Option.map (fun side -> side.code) diff.right
let ensure_alive diff = if diff.destroyed then Error Error.Destroyed else Ok ()

let parse_error_message = function
  | Parser.Empty -> "empty diff"
  | Parser.Malformed { line; message } ->
      Printf.sprintf "line %d: %s" line message

let color red green blue =
  match Color.rgba ~red ~green ~blue ~alpha:255 with
  | Ok value -> value
  | Error _ -> Color.white

let added_background = color 26 77 26
let removed_background = color 77 26 26
let added_foreground = color 34 197 94
let removed_foreground = color 239 68 68
let context_foreground = color 204 204 204

let line_style line =
  match line.Parser.kind with
  | Parser.Added -> Some (added_foreground, added_background)
  | Parser.Removed -> Some (removed_foreground, removed_background)
  | Parser.Context | Parser.Meta -> Some (context_foreground, Color.transparent)

let styled_line line =
  let fg, bg = Option.value (line_style line) ~default:(Color.white, Color.transparent) in
  Styled.chunk ~fg ~bg line.text

let content_for_lines lines =
  let chunks = ref [] in
  List.iteri
    (fun index line ->
      chunks := styled_line line :: !chunks;
      if index < List.length lines - 1 then chunks := Styled.chunk "\n" :: !chunks)
    lines;
  Styled.create (List.rev !chunks)

let plain_content lines = String.concat "\n" (List.map Parser.line_text lines)

let line_number_config lines =
  let numbers = ref [] in
  let hidden = ref [] in
  let signs = ref [] in
  List.iteri
    (fun index line ->
      (match line.Parser.new_number, line.Parser.old_number with
      | Some number, _ -> numbers := (index, number) :: !numbers
      | None, Some number -> numbers := (index, number) :: !numbers
      | None, None -> hidden := index :: !hidden);
      let sign =
        match line.kind with
        | Parser.Added -> Some { Line_number.before = Some "+"; before_color = Some added_foreground; after = None; after_color = None }
        | Parser.Removed -> Some { Line_number.before = Some "-"; before_color = Some removed_foreground; after = None; after_color = None }
        | Parser.Context | Parser.Meta -> None
      in
      Option.iter (fun value -> signs := (index, value) :: !signs) sign)
    lines;
  List.rev !numbers, List.rev !hidden, List.rev !signs

let make_code diff ~id ~lines =
  let styled = content_for_lines lines in
  let content = plain_content lines in
  match
    Code.create diff.context ~id ~content ?filetype:diff.filetype
      ?tree_sitter_client:diff.tree_sitter_client
      ?background:diff.background
      ~syntax_style:diff.syntax_style ~draw_unstyled_text:false
      ~initial_styled_text:styled ()
  with
  | Error error -> Error error
  | Ok code ->
      (match Code.set_wrap_mode code diff.wrap_mode with
      | Error error -> Code.destroy code; Error error
      | Ok () -> Ok code)

let make_side diff ~id ~lines =
  let numbers, hidden, signs = line_number_config lines in
  match make_code diff ~id:(id ^ "-code") ~lines with
  | Error error -> Error error
  | Ok code ->
      (match
         Line_number.create diff.context ~id:(id ^ "-numbers")
           ~target:(Line_number.target_of_code code) ~line_numbers:numbers
           ~hide_line_numbers:hidden ~line_signs:signs
           ~show_line_numbers:diff.show_line_numbers ()
       with
      | Error error -> Code.destroy code; Error error
      | Ok line_number -> Ok { code; line_number })

let destroy_side side =
  Line_number.destroy side.line_number;
  Code.destroy side.code

let detach_current diff =
  Option.iter
    (fun text ->
      ignore (Renderable.Private.detach ~parent:diff.renderable ~child:(Text.as_renderable text));
      Text.destroy text)
    diff.error_text;
  diff.error_text <- None;
  Option.iter
    (fun side ->
      ignore (Renderable.Private.detach ~parent:diff.renderable
                ~child:(Line_number.as_renderable side.line_number));
      destroy_side side)
    diff.left;
  Option.iter
    (fun side ->
      ignore (Renderable.Private.detach ~parent:diff.renderable
                ~child:(Line_number.as_renderable side.line_number));
      destroy_side side)
    diff.right;
  diff.left <- None;
  diff.right <- None

let split_hunk hunk =
  let left = ref [] in
  let right = ref [] in
  let removed = ref [] in
  let added = ref [] in
  let flush () =
    let count = max (List.length !removed) (List.length !added) in
    for index = 0 to count - 1 do
      (match List.nth_opt (List.rev !removed) index with
      | Some line -> left := line :: !left
      | None -> left := { Parser.kind = Parser.Context; text = ""; old_number = None; new_number = None } :: !left);
      (match List.nth_opt (List.rev !added) index with
      | Some line -> right := line :: !right
      | None -> right := { Parser.kind = Parser.Context; text = ""; old_number = None; new_number = None } :: !right)
    done;
    removed := [];
    added := []
  in
  List.iter
    (fun line ->
      match line.Parser.kind with
      | Parser.Removed -> removed := line :: !removed
      | Parser.Added -> added := line :: !added
      | Parser.Context | Parser.Meta -> flush (); left := line :: !left; right := line :: !right)
    hunk.Parser.lines;
  flush ();
  List.rev !left, List.rev !right

let rec is_descendant renderable ancestor =
  if renderable == ancestor then true
  else
    match Renderable.parent renderable with
    | None -> false
    | Some parent -> is_descendant parent ancestor

let synchronize_scroll source target =
  Text_buffer_renderable.set_scroll
    (Code.text_buffer_renderable target)
    ~x:(Code.scroll_x source) ~y:(Code.scroll_y source)

let install_behavior diff =
  let mouse_event _renderable event =
    let split_view = match diff.view with Split -> true | Unified -> false in
    if diff.sync_scroll && split_view
       && Renderable.mouse_kind event = Renderable.Scroll then
      match Renderable.mouse_target event, diff.left, diff.right with
      | Some target, Some left, Some right when is_descendant target (Code.as_renderable left.code) ->
          ignore (synchronize_scroll left.code right.code)
      | Some target, Some left, Some right when is_descendant target (Code.as_renderable right.code) ->
          ignore (synchronize_scroll right.code left.code)
      | _ -> ()
  in
  Renderable.Private.set_behavior diff.renderable
    (Renderable.Private.make_behavior ~mouse_event ())

let build diff =
  detach_current diff;
  match diff.parsed with
  | None ->
      (match diff.parse_error with
      | None -> Ok ()
      | Some error ->
          let message =
            Printf.sprintf "Error parsing diff: %s\n%s"
              (parse_error_message error) diff.content
          in
          Result.bind
            (Text.create diff.context ~id:"diff-error"
               ~content:(Styled.of_string message) ())
            (fun text ->
              Result.bind
                (Layout_children.add (Layout_children.Private.of_renderable diff.renderable)
                   (Text.as_renderable text))
                (fun _ -> diff.error_text <- Some text; Ok ())))
  | Some patch ->
      let result =
        match diff.view with
        | Unified ->
            let lines = Parser.unified_lines patch in
            Result.map (fun side -> diff.left <- Some side) (make_side diff ~id:"unified" ~lines)
        | Split ->
            let left_lines, right_lines =
              List.fold_left
                (fun (left, right) hunk ->
                  let hunk_left, hunk_right = split_hunk hunk in
                  left @ hunk_left, right @ hunk_right)
                ([], []) patch.hunks
            in
            Result.bind (make_side diff ~id:"left" ~lines:left_lines) (fun left ->
                Result.bind (make_side diff ~id:"right" ~lines:right_lines) (fun right ->
                    diff.left <- Some left;
                    diff.right <- Some right;
                    Ok ()))
      in
      match result with
      | Error error -> detach_current diff; Error error
      | Ok () ->
          let attach side =
            Renderable.Private.attach ~parent:diff.renderable
              ~child:(Line_number.as_renderable side.line_number)
              ~index:(match diff.view with Unified -> 0 | Split -> 0)
          in
          let attach_side side = Result.map (fun _ -> ()) (attach side) in
          match diff.left with
          | None -> Ok ()
          | Some left ->
              Result.bind (attach_side left) (fun () ->
                  match diff.right with
                  | None -> Ok ()
                  | Some right ->
                      Result.bind
                        (Result.map (fun _ -> ())
                           (Renderable.set_flex_grow
                              (Line_number.as_renderable right.line_number)
                              (Some 1.0)))
                        (fun () -> attach_side right))

let set_content diff value =
  match ensure_alive diff with
  | Error error -> Error error
  | Ok () ->
      diff.content <- value;
      if String.equal value "" then begin
        diff.parsed <- None;
        diff.parse_error <- None;
        build diff
      end else
        match Parser.parse value with
        | Error error -> diff.parsed <- None; diff.parse_error <- Some error; build diff
        | Ok patch -> diff.parsed <- Some patch; diff.parse_error <- None; build diff

let create context ?id ?(content = "") ?(view = Unified) ?filetype ?syntax_style
    ?tree_sitter_client ?background ?(sync_scroll = true) ?(show_line_numbers = true)
    ?(wrap_mode = Text_buffer_view.No_wrap) () =
  let syntax_style, owns_syntax_style =
    match syntax_style with Some value -> value, false | None -> Syntax_style.create (), true
  in
  match Renderable.Private.create context ?id () with
  | Error error -> if owns_syntax_style then Syntax_style.destroy syntax_style; Error error
  | Ok renderable ->
      let diff =
        {
          renderable; context; content; view; filetype; syntax_style;
          owns_syntax_style; tree_sitter_client; background; sync_scroll; show_line_numbers;
          wrap_mode; parsed = None; parse_error = None; left = None; right = None;
          error_text = None;
          destroyed = false;
        }
      in
      install_behavior diff;
      let result =
        Result.bind (Renderable.set_flex_direction renderable
                       (match view with Unified -> Yoga.Flex_column | Split -> Yoga.Flex_row))
          (fun () -> set_content diff content)
      in
      (match result with
      | Ok () -> Ok diff
      | Error error ->
          Renderable.destroy renderable;
          if owns_syntax_style then Syntax_style.destroy syntax_style;
          Error error)

let set_view diff value =
  match ensure_alive diff with
  | Error error -> Error error
  | Ok () ->
      diff.view <- value;
      Result.bind
        (Renderable.set_flex_direction diff.renderable
           (match value with Unified -> Yoga.Flex_column | Split -> Yoga.Flex_row))
        (fun () -> build diff)

let set_sync_scroll diff value = ensure_alive diff |> Result.map (fun () -> diff.sync_scroll <- value)

let set_show_line_numbers diff value =
  match ensure_alive diff with
  | Error error -> Error error
  | Ok () ->
      diff.show_line_numbers <- value;
      List.iter (fun side -> ignore (Line_number.set_show_line_numbers side.line_number value))
        (List.filter_map (fun value -> value) [ diff.left; diff.right ]);
      Ok ()

let hunk_count diff = match diff.parsed with None -> 0 | Some patch -> List.length patch.hunks

let selected_text diff =
  match diff.left, diff.right with
  | Some side, _ -> Code.selected_text side.code
  | None, Some side -> Code.selected_text side.code
  | None, None -> Ok ""

let destroy diff =
  if not diff.destroyed then begin
    diff.destroyed <- true;
    detach_current diff;
    Renderable.destroy diff.renderable;
    if diff.owns_syntax_style then Syntax_style.destroy diff.syntax_style
  end
