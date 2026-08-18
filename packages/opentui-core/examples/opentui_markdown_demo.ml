(* Port of vendor/opentui/packages/examples/src/markdown-demo.ts.

   A scrollable MarkdownRenderable showcase: rich inline formatting, tables,
   quotes, lists, and fenced code, with theme cycling, conceal toggling, a
   simulated streaming render, and selection support.

   Note: the reference highlights fenced code blocks through bundled
   tree-sitter parsers. The OCaml port does not yet ship a tree-sitter runtime
   (see the tree-sitter backlog), so fences render as plain fallback text,
   matching the reference behavior for unsupported parser languages. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module Util = Opentui_examples_lib.Util
module Box = O.Renderables.Box
module Text = O.Renderables.Text
module Markdown = O.Renderables.Markdown
module Scroll_box = O.Renderables.Scroll_box
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler
module Clock = O.Lib.Clock

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let color = Util.color_of_hex

let md_content =
  {md|
# OpenTUI Markdown Demo

Welcome to the **MarkdownRenderable** showcase! This demonstrates automatic table alignment and syntax highlighting.

```ts
interface StreamChunk {
  id: string
  index: number
  text: string
}

export function appendMarkdownChunk(buffer: string, chunk: StreamChunk): string {
  const prefix = chunk.index === 0 ? "" : "\n"
  return buffer + prefix + chunk.text
}
```

The fenced block above appears near the top so streaming mode exercises a larger Code block before the rest of the document arrives.

## Features

- Automatic **table column alignment** based on content width
- Proper handling of `inline code`, **bold**, and *italic* in tables
- Multiple syntax themes to choose from
- Conceal mode hides formatting markers
- Top-level document layout for assistant-style prose, tables, quotes, and code fences

## Renderer Stress Cases

### Interleaved Code

Start with a short conclusion before any code appears.

```ts
export function parse(input: string) {
  return input.trim().split(/\s+/)
}
```

Then continue with prose immediately after the code block. This should not inherit code styling or indentation.

Final paragraph after a second fence with `inline code`, **bold text**, and _emphasis_ mixed together.

### Lists With Code

1. First ordered item with `inline code`.
2. Second ordered item before a nested list:
   - Nested bullet with a long phrase that should wrap without swallowing the marker or changing indentation.
   - Nested bullet before fenced code:

     ```ts
     const nested = true
     ```

3. Third ordered item after the nested fence.

### Quote, Table, Diff

> Quoted note after the list. It should preserve quote styling while using the renderer's blockquote marker.

| Feature | Stress |
| --- | --- |
| Markdown | prose/code/table interleave |
| Renderer | wrapping and spacing |

```diff
- const renderer = oldMarkdown
+ const renderer = experimentalMarkdown
```

Final paragraph with [docs](https://opentui.dev) and `https://example.com/from-code`.

---

## Comparison Table

| Feature | Status | Priority | Notes |
|---|---|---|---|
| Table alignment | **Done** | High | Uses `marked` parser |
| Conceal mode | *Working* | Medium | Hides formatting markers |
| Theme switching | **Done** | Low | Multiple themes available |
| Unicode support | 日本語 | High | CJK characters |

After a table, normal prose should resume without being treated as another row or inheriting table spacing. This paragraph intentionally starts right after the comparison grid.

- Follow-up bullet with **bold text** and `inline code`.
- Another bullet that wraps with enough text to prove list indentation still works after a table renderable has been emitted.
- Final bullet before the next heading.

This paragraph follows the list and should return to normal prose spacing before the next heading.

1. First ordered follow-up with **emphasis** after the unordered list.
2. Second ordered follow-up with `inline code` and enough text to wrap onto another line.
3. Third ordered follow-up before returning to prose.

This paragraph follows the numeric list and should align like ordinary body text.

## Code Examples

Here's how to use it:

```typescript
import { MarkdownRenderable } from "@opentui/core"
```

And a JSON configuration example:

```json
{
  "name": "opentui-markdown-demo",
  "theme": "github",
  "features": ["table-alignment", "syntax-highlighting", "conceal-mode"]
}
```

## Light Theme Fallback Checks

Press `T` until **GitHub Light**. These fences intentionally skip syntax
highlighting and should still inherit the theme text color.

Unlabeled fenced block:

```
this fence has no language tag
it should stay readable in GitHub Light
```

Unsupported parser fallback:

```toml
title = "GitHub Light"
status = "fallback text should stay readable"
```

### API Reference

| Method | Parameters | Returns | Description |
|---|---|---|---|
| `constructor` | `ctx, options` | `MarkdownRenderable` | Create new instance |
| `clearCache` | none | `void` | Force re-render content |

## Inline Formatting Examples

| Style | Syntax | Rendered |
|---|---|---|
| Bold | `**text**` | **bold text** |
| Italic | `*text*` | *italic text* |
| Code | `code` | `inline code` |
| Link | `[text](url)` | [OpenTUI](https://github.com) |

## Mixed Content

> **Note**: This blockquote contains **bold** and `code` formatting.
> It should render correctly with proper styling.

### Emoji Support

| Emoji | Name | Category |
|---|---|---|
| 🚀 | Rocket | Transport |
| 🎨 | Palette | Art |
| ⚡ | Lightning | Nature |
| 🔥 | Fire | Nature |

---

## Alignment Examples

| Left | Center | Right |
|:---|:---:|---:|
| L1 | C1 | R1 |
| Left aligned | Centered text | Right aligned |
| Short | Medium length | Longer content here |

## Performance

The table alignment uses:
1. AST-based parsing with `marked`
2. Caching for repeated content
3. Smart width calculation accounting for concealed chars

---

*Press `?` for keybindings*
|md}

let rgba_of_hex hex =
  match O.Lib.Rgba.of_hex hex with
  | Ok value -> value
  | Error message -> invalid_arg ("invalid hex color " ^ hex ^ ": " ^ message)

let style_definition ?fg ?bg ?(bold = false) ?(italic = false)
    ?(underline = false) () : O.Syntax_style.style_definition_input =
  {
    fg = Option.map rgba_of_hex fg;
    bg = Option.map rgba_of_hex bg;
    bold = Some bold;
    italic = Some italic;
    underline = Some underline;
    dim = None;
  }

let hex_style fg = style_definition ~fg ()

type theme = {
  name : string;
  bg : string;
  styles : (string * O.Syntax_style.style_definition_input) list;
}

let github_light_theme =
  {
    name = "GitHub Light";
    bg = "#FFFFFF";
    styles =
      [
        ("keyword", style_definition ~fg:"#CF222E" ~bold:true ());
        ("string", hex_style "#0A3069");
        ("comment", style_definition ~fg:"#6E7781" ~italic:true ());
        ("number", hex_style "#0550AE");
        ("function", hex_style "#8250DF");
        ("type", hex_style "#953800");
        ("operator", hex_style "#CF222E");
        ("variable", hex_style "#24292F");
        ("property", hex_style "#0550AE");
        ("punctuation.bracket", hex_style "#24292F");
        ("punctuation.delimiter", hex_style "#57606A");
        ("markup.heading", style_definition ~fg:"#0550AE" ~bold:true ());
        ( "markup.heading.1",
          style_definition ~fg:"#1A7F37" ~bold:true ~italic:true ~underline:true
            () );
        ("markup.heading.2", style_definition ~fg:"#0550AE" ~bold:true ());
        ("markup.heading.3", hex_style "#8250DF");
        ("markup.bold", style_definition ~fg:"#24292F" ~bold:true ());
        ("markup.strong", style_definition ~fg:"#24292F" ~bold:true ());
        ("markup.italic", style_definition ~fg:"#24292F" ~italic:true ());
        ("markup.list", hex_style "#CF222E");
        ("markup.quote", style_definition ~fg:"#6E7781" ~italic:true ());
        ("markup.raw", style_definition ~fg:"#24292F" ~bg:"#F6F8FA" ());
        ("markup.raw.block", style_definition ~fg:"#24292F" ~bg:"#F6F8FA" ());
        ("markup.raw.inline", style_definition ~fg:"#24292F" ~bg:"#F6F8FA" ());
        ("markup.link", style_definition ~fg:"#0969DA" ~underline:true ());
        ("markup.link.label", style_definition ~fg:"#0A3069" ~underline:true ());
        ("markup.link.url", style_definition ~fg:"#0969DA" ~underline:true ());
        ("diff.plus", hex_style "#1A7F37");
        ("diff.minus", hex_style "#CF222E");
        ("label", hex_style "#1A7F37");
        ("conceal", hex_style "#6E7781");
        ("punctuation.special", hex_style "#57606A");
        ("default", hex_style "#24292F");
      ];
  }

let github_dark_theme =
  {
    name = "GitHub Dark";
    bg = "#0D1117";
    styles =
      [
        ("keyword", style_definition ~fg:"#FF7B72" ~bold:true ());
        ("string", hex_style "#A5D6FF");
        ("comment", style_definition ~fg:"#8B949E" ~italic:true ());
        ("number", hex_style "#79C0FF");
        ("function", hex_style "#D2A8FF");
        ("type", hex_style "#FFA657");
        ("operator", hex_style "#FF7B72");
        ("variable", hex_style "#E6EDF3");
        ("property", hex_style "#79C0FF");
        ("punctuation.bracket", hex_style "#F0F6FC");
        ("punctuation.delimiter", hex_style "#C9D1D9");
        ("markup.heading", style_definition ~fg:"#58A6FF" ~bold:true ());
        ( "markup.heading.1",
          style_definition ~fg:"#00FF88" ~bold:true ~italic:true ~underline:true
            () );
        ("markup.heading.2", style_definition ~fg:"#00D7FF" ~bold:true ());
        ("markup.heading.3", hex_style "#FF69B4");
        ("markup.bold", style_definition ~fg:"#F0F6FC" ~bold:true ());
        ("markup.strong", style_definition ~fg:"#F0F6FC" ~bold:true ());
        ("markup.italic", style_definition ~fg:"#F0F6FC" ~italic:true ());
        ("markup.list", hex_style "#FF7B72");
        ("markup.quote", style_definition ~fg:"#8B949E" ~italic:true ());
        ("markup.raw", style_definition ~fg:"#A5D6FF" ~bg:"#161B22" ());
        ("markup.raw.block", style_definition ~fg:"#A5D6FF" ~bg:"#161B22" ());
        ("markup.raw.inline", style_definition ~fg:"#A5D6FF" ~bg:"#161B22" ());
        ("markup.link", style_definition ~fg:"#58A6FF" ~underline:true ());
        ("markup.link.label", style_definition ~fg:"#A5D6FF" ~underline:true ());
        ("markup.link.url", style_definition ~fg:"#58A6FF" ~underline:true ());
        ("diff.plus", hex_style "#3FB950");
        ("diff.minus", hex_style "#F85149");
        ("label", hex_style "#7EE787");
        ("conceal", hex_style "#6E7681");
        ("punctuation.special", hex_style "#8B949E");
        ("default", hex_style "#E6EDF3");
      ];
  }

let monokai_theme =
  {
    name = "Monokai";
    bg = "#272822";
    styles =
      [
        ("keyword", style_definition ~fg:"#F92672" ~bold:true ());
        ("string", hex_style "#E6DB74");
        ("comment", style_definition ~fg:"#75715E" ~italic:true ());
        ("number", hex_style "#AE81FF");
        ("function", hex_style "#A6E22E");
        ("type", style_definition ~fg:"#66D9EF" ~italic:true ());
        ("operator", hex_style "#F92672");
        ("variable", hex_style "#F8F8F2");
        ("property", hex_style "#A6E22E");
        ("punctuation.bracket", hex_style "#F8F8F2");
        ("punctuation.delimiter", hex_style "#F8F8F2");
        ("markup.heading", style_definition ~fg:"#A6E22E" ~bold:true ());
        ( "markup.heading.1",
          style_definition ~fg:"#F92672" ~bold:true ~italic:true ~underline:true
            () );
        ("markup.heading.2", style_definition ~fg:"#66D9EF" ~bold:true ());
        ("markup.heading.3", hex_style "#E6DB74");
        ("markup.bold", style_definition ~fg:"#F8F8F2" ~bold:true ());
        ("markup.strong", style_definition ~fg:"#F8F8F2" ~bold:true ());
        ("markup.italic", style_definition ~fg:"#F8F8F2" ~italic:true ());
        ("markup.list", hex_style "#F92672");
        ("markup.quote", style_definition ~fg:"#75715E" ~italic:true ());
        ("markup.raw", style_definition ~fg:"#E6DB74" ~bg:"#3E3D32" ());
        ("markup.raw.block", style_definition ~fg:"#E6DB74" ~bg:"#3E3D32" ());
        ("markup.raw.inline", style_definition ~fg:"#E6DB74" ~bg:"#3E3D32" ());
        ("markup.link", style_definition ~fg:"#66D9EF" ~underline:true ());
        ("markup.link.label", style_definition ~fg:"#E6DB74" ~underline:true ());
        ("markup.link.url", style_definition ~fg:"#66D9EF" ~underline:true ());
        ("diff.plus", hex_style "#A6E22E");
        ("diff.minus", hex_style "#F92672");
        ("label", hex_style "#A6E22E");
        ("conceal", hex_style "#75715E");
        ("punctuation.special", hex_style "#75715E");
        ("default", hex_style "#F8F8F2");
      ];
  }

let nord_theme =
  {
    name = "Nord";
    bg = "#2E3440";
    styles =
      [
        ("keyword", style_definition ~fg:"#81A1C1" ~bold:true ());
        ("string", hex_style "#A3BE8C");
        ("comment", style_definition ~fg:"#616E88" ~italic:true ());
        ("number", hex_style "#B48EAD");
        ("function", hex_style "#88C0D0");
        ("type", hex_style "#8FBCBB");
        ("operator", hex_style "#81A1C1");
        ("variable", hex_style "#D8DEE9");
        ("property", hex_style "#88C0D0");
        ("punctuation.bracket", hex_style "#ECEFF4");
        ("punctuation.delimiter", hex_style "#D8DEE9");
        ("markup.heading", style_definition ~fg:"#88C0D0" ~bold:true ());
        ( "markup.heading.1",
          style_definition ~fg:"#8FBCBB" ~bold:true ~italic:true ~underline:true
            () );
        ("markup.heading.2", style_definition ~fg:"#81A1C1" ~bold:true ());
        ("markup.heading.3", hex_style "#B48EAD");
        ("markup.bold", style_definition ~fg:"#ECEFF4" ~bold:true ());
        ("markup.strong", style_definition ~fg:"#ECEFF4" ~bold:true ());
        ("markup.italic", style_definition ~fg:"#ECEFF4" ~italic:true ());
        ("markup.list", hex_style "#81A1C1");
        ("markup.quote", style_definition ~fg:"#616E88" ~italic:true ());
        ("markup.raw", style_definition ~fg:"#A3BE8C" ~bg:"#3B4252" ());
        ("markup.raw.block", style_definition ~fg:"#A3BE8C" ~bg:"#3B4252" ());
        ("markup.raw.inline", style_definition ~fg:"#A3BE8C" ~bg:"#3B4252" ());
        ("markup.link", style_definition ~fg:"#88C0D0" ~underline:true ());
        ("markup.link.label", style_definition ~fg:"#A3BE8C" ~underline:true ());
        ("markup.link.url", style_definition ~fg:"#88C0D0" ~underline:true ());
        ("diff.plus", hex_style "#A3BE8C");
        ("diff.minus", hex_style "#BF616A");
        ("label", hex_style "#A3BE8C");
        ("conceal", hex_style "#4C566A");
        ("punctuation.special", hex_style "#616E88");
        ("default", hex_style "#D8DEE9");
      ];
  }

let themes =
  [ github_dark_theme; github_light_theme; monokai_theme; nord_theme ]

type stream_state = Normal | Streaming | Complete | Stopped

type demo = {
  renderer : O.Renderer.t;
  parent : Box.t;
  title_box : Box.t;
  scroll_frame : Box.t;
  instructions : Text.t;
  help_modal : Box.t;
  help_content : Text.t;
  scroll_box : Scroll_box.t;
  mutable markdown : Markdown.t;
  status : Text.t;
  mutable syntax_style : O.Syntax_style.t;
  mutable theme_index : int;
  mutable conceal_enabled : bool;
  mutable showing_help : bool;
  clock : Clock.t;
  mutable stream_timer : Clock.timer option;
  mutable stream_position : int;
  mutable stream_generation : int;
  mutable stream_state : stream_state;
}

let current_theme demo = List.nth themes demo.theme_index

let make_markdown renderer ~theme ~syntax_style ~conceal ?(content = md_content)
    ?(streaming = false) () =
  let default_fg =
    match List.assoc_opt "default" theme.styles with
    | Some def -> def.O.Syntax_style.fg
    | None -> None
  in
  let fg =
    match
      Option.map
        (fun rgba ->
          match O.Lib.Rgba.to_color rgba with
          | Ok color -> color
          | Error error -> invalid_arg (O.Native.Error.message error))
        default_fg
    with
    | Some color -> color
    | None -> O.Color.white
  in
  let markdown =
    expect_ok
      (Markdown.create
         (O.Renderer.context renderer)
         ~id:"markdown-display" ~content ~syntax_style ~fg ~bg:(color theme.bg)
         ~conceal ~streaming
         ~table_options:
           {
             O.Renderables.Markdown.show_borders = true;
             outer_border = true;
             cell_padding_x = 1;
             cell_padding_y = 0;
             column_width_mode = O.Renderables.Text_table.Content;
           }
         ())
  in
  ignore
    (expect_ok
       (O.Renderable.set_width
          (Markdown.as_renderable markdown)
          (O.Yoga.Percent 100.0)));
  markdown

let theme_default_color theme =
  match List.assoc_opt "default" theme.styles with
  | Some def -> (
      match def.O.Syntax_style.fg with
      | Some rgba -> color (O.Lib.Rgba.to_hex rgba)
      | None -> O.Color.white)
  | None -> O.Color.white

let with_fg fg text = S.create [ S.chunk ~fg text ]

let stream_state_label = function
  | Normal -> "NORMAL"
  | Streaming -> "STREAMING"
  | Complete -> "COMPLETE"
  | Stopped -> "STOPPED"

let is_streaming = function
  | Streaming -> true
  | Normal | Complete | Stopped -> false

let set_status demo =
  let theme = current_theme demo in
  let stream_status = stream_state_label demo.stream_state in
  let text =
    Printf.sprintf "Theme: %s | Conceal: %s | Mode: %s | Press T/C/S/X/?"
      theme.name
      (if demo.conceal_enabled then "ON" else "OFF")
      stream_status
  in
  ignore
    (expect_ok
       (Text.set_content demo.status (with_fg (theme_default_color theme) text)))

let cancel_stream_timer demo =
  match demo.stream_timer with
  | None -> ()
  | Some timer ->
      Clock.cancel demo.clock timer;
      demo.stream_timer <- None

let stop_streaming demo =
  cancel_stream_timer demo;
  demo.stream_generation <- demo.stream_generation + 1;
  if Markdown.streaming demo.markdown then
    ignore (expect_ok (Markdown.set_streaming demo.markdown false));
  demo.stream_state <- Stopped;
  set_status demo

let restore_full_markdown demo =
  stop_streaming demo;
  ignore (expect_ok (Markdown.set_content demo.markdown md_content));
  demo.stream_position <- 0;
  demo.stream_state <- Normal;
  set_status demo

let stream_chunk_size = 48
let stream_delay = 0.05

let rec schedule_stream_tick demo generation =
  if
    is_streaming demo.stream_state
    && Int.equal generation demo.stream_generation
  then
    let timer =
      Clock.schedule demo.clock ~delay:stream_delay (fun () ->
          demo.stream_timer <- None;
          if
            is_streaming demo.stream_state
            && Int.equal generation demo.stream_generation
          then begin
            let content_length = String.length md_content in
            let next_position =
              min content_length (demo.stream_position + stream_chunk_size)
            in
            let next_content = String.sub md_content 0 next_position in
            ignore (expect_ok (Markdown.set_content demo.markdown next_content));
            demo.stream_position <- next_position;
            if Int.equal next_position content_length then begin
              ignore (expect_ok (Markdown.set_streaming demo.markdown false));
              demo.stream_state <- Complete;
              set_status demo
            end
            else begin
              set_status demo;
              schedule_stream_tick demo generation
            end
          end)
    in
    demo.stream_timer <- Some timer

let start_streaming demo =
  cancel_stream_timer demo;
  demo.stream_generation <- demo.stream_generation + 1;
  let generation = demo.stream_generation in
  demo.stream_position <- 0;
  demo.stream_state <- Streaming;
  ignore (expect_ok (Markdown.set_streaming demo.markdown true));
  ignore (expect_ok (Markdown.set_content demo.markdown ""));
  Scroll_box.set_sticky_scroll demo.scroll_box true;
  Scroll_box.set_sticky_start demo.scroll_box (Some Scroll_box.Bottom);
  set_status demo;
  schedule_stream_tick demo generation

let refresh_chrome demo =
  let theme = current_theme demo in
  let fg = theme_default_color theme in
  ignore
    (expect_ok
       (Text.set_content demo.instructions
          (with_fg fg "ESC to return | Press ? for keybindings")));
  ignore
    (expect_ok
       (Text.set_content demo.help_content
          (with_fg fg
             "Theme:\n\
             \  T : Cycle through themes\n\n\
              View Controls:\n\
             \  C : Toggle concealment\n\n\
              Streaming:\n\
             \  S : Start/restart streaming\n\
             \  X : Stop streaming\n\n\
              Other:\n\
             \  ? : Toggle this help screen\n\
             \  ESC : Close help or exit\n\
             \  Ctrl+C : Exit\n\
             \  Backtick : Toggle console")))

let apply_theme demo =
  let theme = current_theme demo in
  ignore
    (expect_ok
       (O.Renderer.set_background_color demo.renderer ~color:(color theme.bg)));
  (* Recreate the markdown node so its default fg/bg follow the theme; the
     renderable has no fg/bg setters, so rebuild in place. *)
  let old_markdown = demo.markdown in
  let old_syntax_style = demo.syntax_style in
  let content = Markdown.content old_markdown in
  let streaming = Markdown.streaming old_markdown in
  let next_style = O.Syntax_style.from_styles theme.styles in
  let markdown =
    make_markdown demo.renderer ~theme ~syntax_style:next_style
      ~conceal:demo.conceal_enabled ~content ~streaming ()
  in
  ignore
    (expect_ok
       (Scroll_box.remove demo.scroll_box (Markdown.as_renderable old_markdown)));
  ignore
    (expect_ok
       (Scroll_box.add demo.scroll_box (Markdown.as_renderable markdown)));
  Markdown.destroy old_markdown;
  O.Syntax_style.destroy old_syntax_style;
  demo.syntax_style <- next_style;
  demo.markdown <- markdown;
  ignore (expect_ok (Box.set_border_color demo.title_box (color "#4ECDC4")));
  ignore (expect_ok (Box.set_background_color demo.title_box (color theme.bg)));
  ignore (expect_ok (Box.set_border_color demo.scroll_frame (color "#6BCF7F")));
  ignore
    (expect_ok (Box.set_background_color demo.scroll_frame (color theme.bg)));
  ignore
    (expect_ok
       (Box.set_title demo.scroll_frame
          (Some ("MarkdownRenderable - " ^ theme.name))));
  ignore
    (expect_ok
       (Box.set_title demo.title_box (Some ("Markdown Demo - " ^ theme.name))));
  ignore (expect_ok (Box.set_background_color demo.help_modal (color theme.bg)));
  refresh_chrome demo;
  set_status demo

let run renderer ~exit =
  let theme = List.nth themes 0 in
  let context = O.Renderer.context renderer in
  let clock =
    match expect_ok (O.Render_context.clock context) with
    | Some clock -> clock
    | None -> invalid_arg "the Markdown demo requires a renderer clock"
  in
  ignore
    (expect_ok
       (O.Renderer.set_background_color renderer ~color:(color theme.bg)));
  let parent = expect_ok (Box.create context ~id:"parent-container" ()) in
  ignore
    (expect_ok
       (O.Renderable.set_flex_direction (Box.as_renderable parent)
          O.Yoga.Flex_column));
  ignore (expect_ok (Box.set_z_index parent 10));
  ignore
    (expect_ok
       (O.Renderable.set_padding (Box.as_renderable parent) ~edge:O.Yoga.All
          (O.Yoga.Point 1.0)));
  ignore
    (expect_ok
       (O.Layout_children.add
          (O.Renderer.children renderer)
          (Box.as_renderable parent)));
  let title_box =
    expect_ok
      (Box.create
         (O.Renderer.context renderer)
         ~id:"title-box" ~border_style:O.Lib.Border.Double
         ~border:O.Lib.Border.All_borders ~border_color:(color "#4ECDC4")
         ~title:("Markdown Demo - " ^ theme.name)
         ~title_alignment:O.Lib.Border.Center ~background_color:(color theme.bg)
         ())
  in
  ignore
    (expect_ok
       (O.Renderable.set_height
          (Box.as_renderable title_box)
          (O.Yoga.Point 3.0)));
  ignore
    (expect_ok
       (O.Layout_children.add (Box.children parent)
          (Box.as_renderable title_box)));
  let instructions =
    expect_ok
      (Text.create context
         ~content:(S.of_string "ESC to return | Press ? for keybindings")
         ())
  in
  ignore
    (expect_ok
       (O.Layout_children.add (Box.children title_box)
          (Text.as_renderable instructions)));
  let help_modal =
    expect_ok
      (Box.create context ~id:"help-modal" ~border_style:O.Lib.Border.Double
         ~border:O.Lib.Border.All_borders ~border_color:(color "#4ECDC4")
         ~background_color:(color theme.bg) ~title:"Keybindings"
         ~title_alignment:O.Lib.Border.Center ())
  in
  ignore
    (expect_ok
       (O.Renderable.set_position_type
          (Box.as_renderable help_modal)
          O.Yoga.Position_absolute));
  ignore
    (expect_ok
       (O.Renderable.set_position
          (Box.as_renderable help_modal)
          ~edge:O.Yoga.Left (O.Yoga.Percent 50.0)));
  ignore
    (expect_ok
       (O.Renderable.set_position
          (Box.as_renderable help_modal)
          ~edge:O.Yoga.Top (O.Yoga.Percent 50.0)));
  ignore
    (expect_ok
       (O.Renderable.set_margin
          (Box.as_renderable help_modal)
          ~edge:O.Yoga.Left (O.Yoga.Point (-30.0))));
  ignore
    (expect_ok
       (O.Renderable.set_margin
          (Box.as_renderable help_modal)
          ~edge:O.Yoga.Top (O.Yoga.Point (-10.0))));
  ignore
    (expect_ok
       (O.Renderable.set_width
          (Box.as_renderable help_modal)
          (O.Yoga.Point 60.0)));
  ignore
    (expect_ok
       (O.Renderable.set_height
          (Box.as_renderable help_modal)
          (O.Yoga.Point 20.0)));
  ignore
    (expect_ok
       (O.Renderable.set_padding
          (Box.as_renderable help_modal)
          ~edge:O.Yoga.All (O.Yoga.Point 2.0)));
  ignore
    (expect_ok (O.Renderable.set_z_index (Box.as_renderable help_modal) 100));
  ignore
    (expect_ok (O.Renderable.set_visible (Box.as_renderable help_modal) false));
  ignore
    (expect_ok
       (O.Layout_children.add
          (O.Renderer.children renderer)
          (Box.as_renderable help_modal)));
  let help_content =
    expect_ok
      (Text.create context
         ~content:
           (S.of_string
              "Theme:\n\
              \  T : Cycle through themes\n\n\
               View Controls:\n\
              \  C : Toggle concealment\n\n\
               Streaming:\n\
              \  S : Start/restart streaming\n\
              \  X : Stop streaming\n\n\
               Other:\n\
              \  ? : Toggle this help screen\n\
              \  ESC : Close help or exit\n\
              \  Ctrl+C : Exit\n\
              \  Backtick : Toggle console")
         ())
  in
  ignore
    (expect_ok
       (O.Layout_children.add (Box.children help_modal)
          (Text.as_renderable help_content)));
  let scroll_frame =
    expect_ok
      (Box.create context ~id:"markdown-scroll-frame"
         ~background_color:(color theme.bg) ~border_style:O.Lib.Border.Single
         ~border:O.Lib.Border.All_borders ~border_color:(color "#6BCF7F")
         ~title:("MarkdownRenderable - " ^ theme.name)
         ~title_alignment:O.Lib.Border.Left ())
  in
  ignore
    (expect_ok
       (O.Renderable.set_flex_grow (Box.as_renderable scroll_frame) (Some 1.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_shrink
          (Box.as_renderable scroll_frame)
          (Some 1.0)));
  ignore
    (expect_ok
       (O.Renderable.set_overflow
          (Box.as_renderable scroll_frame)
          O.Yoga.Overflow_hidden));
  ignore
    (expect_ok
       (O.Renderable.set_padding
          (Box.as_renderable scroll_frame)
          ~edge:O.Yoga.Horizontal (O.Yoga.Point 2.0)));
  ignore
    (expect_ok
       (O.Renderable.set_padding
          (Box.as_renderable scroll_frame)
          ~edge:O.Yoga.Vertical (O.Yoga.Point 1.0)));
  ignore
    (expect_ok
       (O.Layout_children.add (Box.children parent)
          (Box.as_renderable scroll_frame)));
  let scroll_box =
    expect_ok
      (Scroll_box.create context ~id:"markdown-scroll-box" ~scroll_y:true
         ~scroll_x:false ())
  in
  ignore
    (expect_ok
       (O.Renderable.set_flex_grow
          (Scroll_box.as_renderable scroll_box)
          (Some 1.0)));
  ignore
    (expect_ok
       (O.Renderable.set_flex_shrink
          (Scroll_box.as_renderable scroll_box)
          (Some 1.0)));
  ignore
    (expect_ok
       (O.Layout_children.add
          (Box.children scroll_frame)
          (Scroll_box.as_renderable scroll_box)));
  let syntax_style = O.Syntax_style.from_styles theme.styles in
  let markdown = make_markdown renderer ~theme ~syntax_style ~conceal:true () in
  ignore
    (expect_ok (Scroll_box.add scroll_box (Markdown.as_renderable markdown)));
  let status = expect_ok (Text.create context ~content:(S.of_string "") ()) in
  ignore
    (expect_ok
       (O.Renderable.set_flex_shrink (Text.as_renderable status) (Some 0.0)));
  ignore
    (expect_ok
       (O.Layout_children.add (Box.children parent) (Text.as_renderable status)));
  ignore (expect_ok (O.Renderable.focus (Scroll_box.as_renderable scroll_box)));
  let demo =
    {
      renderer;
      parent;
      title_box;
      scroll_frame;
      instructions;
      help_modal;
      help_content;
      scroll_box;
      markdown;
      status;
      syntax_style;
      theme_index = 0;
      conceal_enabled = true;
      showing_help = false;
      clock;
      stream_timer = None;
      stream_position = 0;
      stream_generation = 0;
      stream_state = Normal;
    }
  in
  ignore
    (expect_ok
       (O.Renderer.attach_before_destroy renderer (fun () ->
            cancel_stream_timer demo)));
  refresh_chrome demo;
  set_status demo;
  let console = O.Renderer.console renderer in
  ignore
    (O.Renderer.on_keypress renderer (fun key_event ->
         match Handler.key_event_kind key_event with
         | Handler.Keyrelease | Handler.Paste -> ()
         | Handler.Keypress ->
             let modifiers = Handler.key_modifiers key_event in
             if (not modifiers.ctrl) && not modifiers.meta then (
               let key = Handler.key key_event in
               (* When the diagnostic console drawer is open, arrow keys scroll
                  it instead of reaching the markdown. *)
               (match key with
               | Key.Named Key.Up -> (
                   match O.Console.visible console with
                   | Ok true -> ignore (expect_ok (O.Console.scroll_up console))
                   | _ -> ())
               | Key.Named Key.Down -> (
                   match O.Console.visible console with
                   | Ok true ->
                       ignore (expect_ok (O.Console.scroll_down console))
                   | _ -> ())
               | _ -> ());
               match key with
               | Key.Named Key.Escape ->
                   (* ESC closes the help overlay, otherwise exits. *)
                   if demo.showing_help then begin
                     demo.showing_help <- false;
                     ignore
                       (expect_ok
                          (O.Renderable.set_visible
                             (Box.as_renderable demo.help_modal)
                             false))
                   end
                   else exit ()
               | Key.Character bytes
                 when String.equal (Bytes.to_string bytes) "?" ->
                   demo.showing_help <- not demo.showing_help;
                   ignore
                     (expect_ok
                        (O.Renderable.set_visible
                           (Box.as_renderable demo.help_modal)
                           demo.showing_help))
               | _ when demo.showing_help -> ()
               | Key.Character bytes -> (
                   match String.lowercase_ascii (Bytes.to_string bytes) with
                   | "t" ->
                       demo.theme_index <-
                         (demo.theme_index + 1) mod List.length themes;
                       apply_theme demo
                   | "c" ->
                       stop_streaming demo;
                       demo.conceal_enabled <- not demo.conceal_enabled;
                       ignore
                         (expect_ok
                            (Markdown.set_conceal demo.markdown
                               demo.conceal_enabled));
                       set_status demo
                   | "s" -> start_streaming demo
                   | "x" -> stop_streaming demo
                   | _ -> ())
               | Key.Named _ -> ())));
  (* Common demo keys: Ctrl+C exits, backtick/quote toggles the console. *)
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer
    ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run env ~init:(fun ~exit renderer ->
      run renderer ~exit)
