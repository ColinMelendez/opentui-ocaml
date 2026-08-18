open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderable = Core.Renderable
module Box = Core.Renderables.Box
module Markdown = Core.Renderables.Markdown
module Scroll_bar = Core.Renderables.Scroll_bar
module Scroll_box = Core.Renderables.Scroll_box
module Text = Core.Renderables.Text
module Yoga = Core.Yoga

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let attach parent child =
  ignore (expect_ok (Core.Layout_children.add parent child))

let () =
  run "opentui-core-scrollbox-demo-layout"
    [
      test "markdown demo ordering keeps a newly visible bar at the trailing edge"
        (fun () ->
          let renderer =
            expect_ok
              (Renderer.create ~output:Renderer.Output.Memory ~width:80l
                 ~height:24l ())
          in
          let context = Renderer.context renderer in
          let parent = expect_ok (Box.create context ~id:"demo-parent" ()) in
          attach (Renderer.children renderer) (Box.as_renderable parent);
          let title =
            expect_ok
              (Box.create context ~id:"demo-title"
                 ~border:Box.all_borders ())
          in
          ignore
            (expect_ok
               (Renderable.set_height (Box.as_renderable title)
                  (Yoga.Point 3.0)));
          attach (Box.children parent) (Box.as_renderable title);
          let instructions =
            expect_ok
              (Text.create context
                 ~content:(Core.Lib.Styled_text.of_string "instructions") ())
          in
          attach (Box.children title) (Text.as_renderable instructions);
          let scroll_box =
            expect_ok
              (Scroll_box.create context ~id:"demo-scroll" ~scroll_y:true ())
          in
          if Scroll_bar.visible (Scroll_box.horizontal_scrollbar scroll_box) then
            fail "horizontal scrollbar was visible despite scroll_x=false";
          ignore
            (expect_ok
               (Renderable.set_height (Scroll_box.as_renderable scroll_box)
                  (Yoga.Percent 100.0)));
          attach (Box.children parent) (Scroll_box.as_renderable scroll_box);
          let content =
            String.concat "\n"
              [ "# OpenTUI Markdown Demo";
                "";
                "Welcome to the **MarkdownRenderable** showcase! This demonstrates automatic table alignment and syntax highlighting.";
                "";
                "```ts";
                "interface StreamChunk {";
                "  id: string";
                "  index: number";
                "  text: string";
                "}";
                "";
                "export function appendMarkdownChunk(buffer: string, chunk: StreamChunk): string {";
                "  return buffer + chunk.text";
                "}";
                "```";
                "";
                "## Features";
                "";
                "- Automatic **table column alignment** based on content width";
                "- Proper handling of `inline code`, **bold**, and *italic* in tables";
                "";
                "| Feature | Status | Priority | Notes |";
                "| --- | --- | --- | --- |";
                "| Table alignment | **Done** | High | Uses parser |";
                "| Conceal mode | *Working* | Medium | Hides markers |";
                "";
                "> Quoted note after the list. It should preserve quote styling.";
                "";
                "```diff";
                "- const renderer = oldMarkdown";
                "+ const renderer = experimentalMarkdown";
                "```";
                "";
                "Final paragraph with [docs](https://opentui.dev) and `inline code`." ]
          in
          let markdown =
            expect_ok (Markdown.create context ~content ())
          in
          ignore
            (expect_ok
               (Scroll_box.add scroll_box (Markdown.as_renderable markdown)));
          let status =
            expect_ok
              (Text.create context
                 ~content:(Core.Lib.Styled_text.of_string "status") ())
          in
          attach (Box.children parent) (Text.as_renderable status);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let root = Scroll_box.as_renderable scroll_box in
          let viewport = Scroll_box.viewport scroll_box in
          let bar = Scroll_bar.as_renderable (Scroll_box.vertical_scrollbar scroll_box) in
          let viewport_right = Renderable.screen_x viewport +. Renderable.width viewport in
          let root_right = Renderable.screen_x root +. Renderable.width root in
          if not (Float.equal (Renderable.screen_x bar) viewport_right)
             || not (Float.equal (Renderable.screen_x bar +. Renderable.width bar) root_right)
          then
            fail
              (Printf.sprintf
                 "demo layout misplaced scrollbar: root=(%.1f,%.1f %.1fx%.1f) viewport=(%.1f,%.1f %.1fx%.1f) bar=(%.1f,%.1f %.1fx%.1f)"
                 (Renderable.screen_x root) (Renderable.screen_y root)
                 (Renderable.width root) (Renderable.height root)
                 (Renderable.screen_x viewport) (Renderable.screen_y viewport)
                 (Renderable.width viewport) (Renderable.height viewport)
                 (Renderable.screen_x bar) (Renderable.screen_y bar)
                 (Renderable.width bar) (Renderable.height bar));
          let buffer = expect_ok (Renderer.current_buffer renderer) in
          let snapshot = expect_ok (Core.Buffer.cell_snapshot buffer) in
          let characters, _, _, _ = snapshot.cells in
          let width = Int32.to_int snapshot.width in
          let cell row column = characters.(row * width + column) in
          let thumb = Int32.of_int 0x2588 in
          if not (Int32.equal (cell 3 79) thumb) then
            fail "scrollbar thumb was not rendered at its laid-out screen position";
          if Int32.equal (cell 3 0) thumb then
            fail "scrollbar thumb was rendered at buffer origin";
          Markdown.destroy markdown;
          Renderer.destroy renderer)
    ]
