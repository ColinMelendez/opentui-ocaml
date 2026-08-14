open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Text = Core.Renderables.Text
module Text_node = Core.Renderables.Text_node
module Text_children = Core.Renderables.Text_children
module Styled_text = Core.Lib.Styled_text

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_native_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Native.Error.message error)

let expect_not_child result =
  match result with
  | Error Core.Error.Not_child -> ()
  | Ok _ -> fail "expected a missing-child error"
  | Error error -> fail (Core.Error.message error)

let expect_invalid_anchor result =
  match result with
  | Error Core.Error.Invalid_anchor -> ()
  | Ok _ -> fail "expected an invalid-anchor error"
  | Error error -> fail (Core.Error.message error)

let expect_same left right =
  if not (left == right) then fail "expected the same retained node"

let () =
  run "opentui-core-text"
    [
      test "text nodes keep strings separate from node children" (fun () ->
          let root = Text_node.create ~id:"root" () in
          let first = Text_node.create ~id:"first" () in
          let second = Text_node.create ~id:"second" () in
          ignore (expect_ok (Text_node.add root (Text_node.String "left")));
          ignore (expect_ok (Text_node.add root (Text_node.Node first)));
          ignore (expect_ok (Text_node.add root (Text_node.String "right")));
          ignore (expect_ok (Text_node.add root (Text_node.Node second)));
          equal int 4 (Text_node.child_count root);
          equal int 2 (List.length (Text_node.get_children root));
          (match Text_node.parent first with
          | None -> fail "first node has no parent"
          | Some parent -> expect_same root parent);
          (match Text_node.find_child_by_id root "second" with
          | None -> fail "second node was not found"
          | Some child -> expect_same second child);
          ignore (expect_ok (Text_node.add ~index:4 root (Text_node.Node first)));
          let nodes = Text_node.get_children root in
          (match nodes with
          | [ first_node; second_node ] ->
              expect_same second first_node;
              expect_same first second_node
          | _ -> fail "same-parent move changed the node count");
          ignore (expect_ok (Text_node.add ~index:0 root (Text_node.Node first)));
          (match Text_node.get_children root with
          | [ first_node; second_node ] ->
              expect_same first first_node;
              expect_same second second_node
          | _ -> fail "backward move changed the node count");
          let other = Text_node.create () in
          ignore (expect_ok (Text_node.add other (Text_node.Node first)));
          equal int 1 (List.length (Text_node.get_children other));
          equal int 1 (List.length (Text_node.get_children root)));
      test "styled text expands and gathers inherited style" (fun () ->
          let red =
            expect_native_ok (Core.Color.rgb ~red:255 ~green:0 ~blue:0)
          in
          let parent = Text_node.create ~fg:red ~attributes:1 () in
          let child = Text_node.create ~attributes:2 () in
          ignore (expect_ok (Text_node.add child (Text_node.String "child")));
          ignore (expect_ok (Text_node.add parent (Text_node.Node child)));
          ignore
            (expect_ok
               (Text_node.add parent
                  (Text_node.Styled
                     (Styled_text.create
                        [Styled_text.chunk ~attributes:4 "styled"]))));
          let gathered = Styled_text.chunks (Text_node.gather parent) in
          equal int 2 (List.length gathered);
          (match gathered with
          | [ first; second ] ->
              equal string "child" first.text;
              equal int 3 first.attributes;
              equal string "styled" second.text;
              equal int 5 second.attributes;
              (match first.fg with
              | None -> fail "inherited foreground was lost"
              | Some color ->
                  let red_channel, green_channel, blue_channel, alpha_channel =
                    Core.Color.channels color
                  in
                  equal int 255 red_channel;
                  equal int 0 green_channel;
                  equal int 0 blue_channel;
                  equal int 255 alpha_channel)
          | _ -> fail "unexpected gathered chunk count");
          let children = Text_children.Private.of_node parent in
          equal int 2 (Text_children.child_count children);
          ignore
            (expect_ok
               (Text_node.insert_before parent (Text_node.String "prefix")
                  ~anchor:child));
          equal int 3 (Text_node.child_count parent);
          ignore (expect_ok (Text_node.remove parent child));
          expect_not_child (Text_node.remove parent child);
          Text_node.clear parent;
          equal int 0 (Text_node.child_count parent));
      test "text lifecycle synchronizes composition before Yoga layout" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:5l ~height:10l) in
          let text =
            expect_ok
              (Text.create (Renderer.context renderer)
                 ~wrap_mode:Core.Text_buffer_view.Char ())
          in
          ignore
            (expect_ok
               (Text.add text (Text_children.String "ABCDEFGHIJ")));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Text.as_renderable text)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let layout = expect_ok (Core.Renderable.layout (Text.as_renderable text)) in
          if Float.abs (layout.height -. 2.0) > 0.0001 then
            fail "text composition did not reach the native measure target";
          equal string "ABCDEFGHIJ"
            (Styled_text.plain_text (Text.content text));
          Renderer.destroy renderer);
      test "manual text content remains independent of text children" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:5l ~height:10l) in
          let text =
            expect_ok
              (Text.create (Renderer.context renderer)
                 ~wrap_mode:Core.Text_buffer_view.Char
                 ~content:(Styled_text.of_string "ABCDE") ())
          in
          ignore
            (expect_ok
               (Text.add text (Text_children.String "FGHIJ")));
          ignore
            (expect_ok
               (Core.Layout_children.add (Renderer.children renderer)
                  (Text.as_renderable text)));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let manual_layout =
            expect_ok (Core.Renderable.layout (Text.as_renderable text))
          in
          if Float.abs (manual_layout.height -. 1.0) > 0.0001 then
            fail "manual content was replaced by text-node children";
          ignore
            (expect_ok
               (Text.set_content text (Styled_text.of_string "ABCDEFGHIJ")));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let updated_layout =
            expect_ok (Core.Renderable.layout (Text.as_renderable text))
          in
          if Float.abs (updated_layout.height -. 2.0) > 0.0001 then
            fail "manual content did not remeasure";
          ignore (expect_ok (Text.clear text));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let cleared_layout =
            expect_ok (Core.Renderable.layout (Text.as_renderable text))
          in
          if Float.abs (cleared_layout.height -. 1.0) > 0.0001 then
            fail "clearing text did not update the measure target";
          Renderer.destroy renderer);
      test "text child operations preserve typed anchor errors" (fun () ->
          let parent = Text_node.create () in
          let other_parent = Text_node.create () in
          let child = Text_node.create () in
          let anchor = Text_node.create () in
          expect_invalid_anchor
            (Text_node.add parent (Text_node.Node parent));
          expect_invalid_anchor
            (Text_node.insert_before parent (Text_node.Node child) ~anchor);
          ignore (expect_ok (Text_node.add other_parent (Text_node.Node child)));
          expect_not_child (Text_node.remove parent child);
          ignore (expect_ok (Text_node.add parent (Text_node.Node anchor)));
          ignore (expect_ok (Text_node.add parent (Text_node.Node child)));
          expect_invalid_anchor
            (Text_node.add child (Text_node.Node parent)))
    ]
