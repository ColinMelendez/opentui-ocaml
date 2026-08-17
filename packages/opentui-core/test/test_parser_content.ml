open Windtrap

module Core = Opentui_core
module Renderer = Core.Renderer
module Renderables = Core.Renderables

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let attach renderer renderable =
  ignore (expect_ok (Core.Layout_children.add (Renderer.children renderer) renderable))

let expect_parser_ok result =
  match result with
  | Ok value -> value
  | Error _ -> fail "unexpected parser error"

let frame renderer =
  let output = Bytes.create 4096 in
  let written =
    expect_ok
      (Core.Buffer.write_resolved_chars
         (expect_ok (Renderer.current_buffer renderer)) ~output
         ~add_line_breaks:false)
  in
  Bytes.sub_string output 0 (Int32.to_int written)

let lines_of_frame ~width value =
  let line_count = String.length value / width in
  let lines = ref [] in
  for index = line_count - 1 downto 0 do
    lines := String.sub value (index * width) width :: !lines
  done;
  !lines

let () =
  run "opentui-core-parser-content"
    [
      test "filetype resolution and injected parser ordering are explicit" (fun () ->
          equal (option string) (Some "typescriptreact")
            (Core.Lib.Tree_sitter_resolve_filetype.path_to_filetype "src/App.TSX");
          equal (option string) (Some "bash")
            (Core.Lib.Tree_sitter_resolve_filetype.path_to_filetype "~/.zshrc");
          equal (option string) (Some "bash")
            (Core.Lib.Tree_sitter_resolve_filetype.info_string_to_filetype ".zshrc");
          equal (option string) (Some "typescriptreact")
            (Core.Lib.Tree_sitter_resolve_filetype.info_string_to_filetype "tsx");
          let client = Core.Lib.Tree_sitter_client.create () in
          let parser : Core.Lib.Tree_sitter_types.parser =
            {
              filetype = "ocaml";
              aliases = [ "ml" ];
              worker_safety = Core.Lib.Tree_sitter_types.Owner_only;
              highlight = (fun _ -> Ok [ { start = 0; end_ = 3; group = "keyword"; meta = None } ]);
            }
          in
          ignore (expect_parser_ok (Core.Lib.Tree_sitter_client.register_parser client parser));
          let conceal_parser : Core.Lib.Tree_sitter_types.parser =
            {
              filetype = "conceal";
              aliases = [];
              worker_safety = Core.Lib.Tree_sitter_types.Owner_only;
              highlight =
                (fun _ ->
                  Ok
                    [
                      {
                        start = 0;
                        end_ = 2;
                        group = "conceal";
                        meta =
                          Some
                            {
                              is_injection = false;
                              injection_lang = None;
                              contains_injection = false;
                              conceal = Some "";
                              conceal_lines = Some "";
                            };
                      };
                    ]);
            }
          in
          ignore (expect_parser_ok (Core.Lib.Tree_sitter_client.register_parser client conceal_parser));
          let parser = Option.get (Core.Lib.Tree_sitter_client.resolve_parser client "ocaml") in
          ignore
            (expect_parser_ok
               (Core.Lib.Tree_sitter_client.run_parser parser ~content:"let"));
          ignore
            (expect_parser_ok
               (Core.Lib.Tree_sitter_client.run_parser parser ~content:"fun"));
          Core.Lib.Tree_sitter_client.destroy client);
      test "Code uses native styled chunks, selection, and parser fallback" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:40l ~height:5l) in
          let style =
            {
              Core.Syntax_style.fg = Some (Core.Lib.Rgba.from_ints 255 0 0);
              bg = None;
              bold = Some true;
              italic = None;
              underline = None;
              dim = None;
            }
          in
          let syntax_style = Core.Syntax_style.create () in
          ignore (Core.Syntax_style.register_style syntax_style "keyword" style);
          let client = Core.Lib.Tree_sitter_client.create () in
          let parser : Core.Lib.Tree_sitter_types.parser =
            {
              filetype = "ocaml";
              aliases = [];
              worker_safety = Core.Lib.Tree_sitter_types.Owner_only;
              highlight = (fun _ -> Ok [ { start = 0; end_ = 3; group = "keyword"; meta = None } ]);
            }
          in
          ignore (expect_parser_ok (Core.Lib.Tree_sitter_client.register_parser client parser));
          let conceal_parser : Core.Lib.Tree_sitter_types.parser =
            {
              filetype = "conceal";
              aliases = [];
              worker_safety = Core.Lib.Tree_sitter_types.Owner_only;
              highlight =
                (fun _ ->
                  Ok
                    [
                      {
                        start = 0;
                        end_ = 2;
                        group = "conceal";
                        meta =
                          Some
                            {
                              is_injection = false;
                              injection_lang = None;
                              contains_injection = false;
                              conceal = Some "";
                              conceal_lines = Some "";
                            };
                      };
                    ]);
            }
          in
          ignore (expect_parser_ok (Core.Lib.Tree_sitter_client.register_parser client conceal_parser));
          let code =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer) ~content:"let x"
                 ~filetype:"ocaml" ~syntax_style ~tree_sitter_client:client ())
          in
          attach renderer (Renderables.Code.as_renderable code);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 1 (List.length (Renderables.Code.highlights code));
          equal string "let x" (Renderables.Code.content code);
          ignore (expect_ok (Renderables.Code.set_selection code ~start:0 ~end_:3 ()));
          equal string "let" (expect_ok (Renderables.Code.selected_text code));
          let fallback =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer) ~content:"plain"
                 ~filetype:"unknown" ())
          in
          (match Renderables.Code.highlight_state fallback with
          | Renderables.Code.Fallback (Core.Lib.Tree_sitter_types.No_parser "unknown") -> ()
          | _ -> fail "Code did not expose its parser fallback state");
          let concealed =
            expect_ok
              (Renderables.Code.create (Renderer.context renderer) ~content:"aa\nbb"
                 ~filetype:"conceal" ~syntax_style ~tree_sitter_client:client ())
          in
          attach renderer (Renderables.Code.as_renderable concealed);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          (match Core.Tree_sitter_styled_text.concealed_line_sources
                   ~content:"aa\nbb"
                   ~highlights:(Renderables.Code.highlights concealed) ~conceal:true with
          | Some [| 1 |] -> ()
          | None ->
              fail
                (Printf.sprintf "concealed source helper returned no mapping (highlights=%d)"
                   (List.length (Renderables.Code.highlights concealed)))
          | Some values ->
              fail
                (Printf.sprintf "concealed source helper returned [%s]"
                   (String.concat "," (List.map string_of_int (Array.to_list values)))));
          (match expect_ok (Renderables.Code.line_info concealed) with
          | { Core.Text_buffer_view.line_sources = sources; _ } ->
              (match Array.to_list sources with
              | [ 1 ] -> ()
              | values ->
                  fail
                    (Printf.sprintf "concealed source line was not mapped: [%s]"
                       (String.concat "," (List.map string_of_int values)))));
          Renderables.Code.destroy concealed;
          Renderables.Code.destroy fallback;
          Renderables.Code.destroy code;
          Core.Lib.Tree_sitter_client.destroy client;
          equal bool false (Core.Syntax_style.is_destroyed syntax_style);
          Core.Syntax_style.destroy syntax_style;
          Renderer.destroy renderer);
      test "styled conversion and links preserve Unicode codepoint ranges" (fun () ->
          let syntax_style = Core.Syntax_style.create () in
          let highlights =
            [
              {
                Core.Lib.Tree_sitter_types.start = 0;
                end_ = 2;
                group = "markup.link.url";
                meta = None;
              };
            ]
          in
          let styled =
            Core.Tree_sitter_styled_text.tree_sitter_to_styled_text
              ~syntax_style ~content:"éx" ~highlights ()
          in
          equal string "éx" (Core.Lib.Styled_text.plain_text styled);
          let links = Core.Detect_links.ranges ~content:"go https://example.test" ~highlights:[] in
          equal int 1 (List.length links);
          equal string "https://example.test" (List.hd links).url;
          let styled_input =
            Core.Lib.Styled_text.create
              [ Core.Lib.Styled_text.chunk ~fg:Core.Color.white ~attributes:7
                  "go https://example.test" ]
          in
          let linked =
            Core.Detect_links.apply ~content:"go https://example.test"
              ~styled_text:styled_input links
          in
          (match Core.Lib.Styled_text.chunks linked with
          | first :: second :: _ ->
              equal int 7 first.attributes;
              equal string "https://example.test" (Option.get second.link)
          | _ -> fail "link detection did not split a styled chunk");
          Core.Syntax_style.destroy syntax_style);
      test "Markdown parses and updates block ownership" (fun () ->
          let parsed = Renderables.Markdown_parser.parse "# Title\n\n**body**\n\n```ocaml\nlet x\n```" in
          equal int 3 (List.length (Renderables.Markdown_parser.tokens parsed));
          equal string "body"
            (Renderables.Markdown_parser.inline_text
               [ Renderables.Markdown_parser.Strong [ Renderables.Markdown_parser.Text "body" ] ]);
          let table = Renderables.Markdown_parser.parse "| A | B |\n| :--- | ---: |\n| x | y |" in
          (match Renderables.Markdown_parser.tokens table with
          | [ Renderables.Markdown_parser.Table { alignments; _ } ] ->
              equal int 2 (List.length alignments)
          | _ -> fail "pipe-delimited Markdown table was not parsed");
          let stable =
            Renderables.Markdown_parser.parse_incremental ~trailing_unstable:0 "# Title" None
          in
          equal int 1 (Renderables.Markdown_parser.stable_token_count stable);
          let renderer = expect_ok (Renderer.create ~width:50l ~height:10l) in
          let markdown =
            expect_ok
              (Renderables.Markdown.create (Renderer.context renderer)
                 ~content:"# Title\n\n**body**" ())
          in
          attach renderer (Renderables.Markdown.as_renderable markdown);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 2 (Renderables.Markdown.block_count markdown);
          ignore (expect_ok (Renderables.Markdown.set_content markdown "# New\n\n- one\n- two"));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 2 (Renderables.Markdown.block_count markdown);
          if not (String.contains (frame renderer) 'N') then fail "updated Markdown was not rendered";
          Renderables.Markdown.destroy markdown;
          Renderer.destroy renderer);
      test "Markdown table alignment markers affect rendered cell origins" (fun () ->
          let renderer = expect_ok (Renderer.create ~width:36l ~height:8l) in
          let markdown =
            expect_ok
              (Renderables.Markdown.create (Renderer.context renderer)
                 ~content:"|L|C|R|\n|:---|:---:|---:|\n|A|B|C|"
                 ~table_options:
                   {
                     show_borders = false;
                     outer_border = false;
                     cell_padding_x = 0;
                     cell_padding_y = 0;
                   }
                 ())
          in
          attach renderer (Renderables.Markdown.as_renderable markdown);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          let lines = lines_of_frame ~width:36 (frame renderer) in
          let data_line =
            List.find_opt
              (fun line ->
                String.contains line 'A' && String.contains line 'B'
                && String.contains line 'C')
              lines
          in
          (match data_line with
          | None -> fail "aligned Markdown table data row was not rendered"
          | Some line ->
              let left = String.index line 'A' in
              let center = String.index line 'B' in
              let right = String.index line 'C' in
              equal int 0 left;
              equal int 18 center;
              equal int 35 right);
          Renderables.Markdown.destroy markdown;
          Renderer.destroy renderer);
      test "Diff parses unified and split views and updates" (fun () ->
          let diff_text = "--- a/file.ml\n+++ b/file.ml\n@@ -1,2 +1,2 @@\n-old\n+new\n same" in
          let parsed = expect_parser_ok (Renderables.Diff_parser.parse diff_text) in
          equal int 1 (List.length parsed.hunks);
          let renderer = expect_ok (Renderer.create ~width:60l ~height:8l) in
          let diff =
            expect_ok
              (Renderables.Diff.create (Renderer.context renderer) ~content:diff_text ())
          in
          attach renderer (Renderables.Diff.as_renderable diff);
          ignore (expect_ok (Renderer.render renderer ~force:true));
          equal int 1 (Renderables.Diff.hunk_count diff);
          ignore (expect_ok (Renderables.Diff.set_view diff Renderables.Diff.Split));
          ignore (expect_ok (Renderer.render renderer ~force:true));
          (match Renderables.Diff.view diff with
          | Renderables.Diff.Split -> ()
          | Renderables.Diff.Unified -> fail "Diff view did not update");
          ignore (expect_ok (Renderables.Diff.set_content diff "not a patch"));
          (match Renderables.Diff.parse_error diff with Some _ -> () | None -> fail "malformed diff was accepted");
          Renderables.Diff.destroy diff;
          Renderer.destroy renderer);
    ]
