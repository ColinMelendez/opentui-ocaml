open Windtrap

module Core = Opentui_core
module Lib = Core.Lib

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> fail (Core.Error.message error)

let expect_rgba result =
  match result with
  | Ok value -> value
  | Error message -> fail message

let expect_native result =
  match result with
  | Ok value -> value
  | Error _ -> fail "unexpected native error"

let expect_int_option expected actual =
  match expected, actual with
  | None, None -> ()
  | Some expected, Some actual -> equal int expected actual
  | None, Some _ | Some _, None -> fail "unexpected optional integer"

let expect_int_array expected actual =
  equal int (Array.length expected) (Array.length actual);
  Array.iteri (fun index value -> equal int value actual.(index)) expected

let expect_float expected actual =
  if Float.abs (expected -. actual) > 0.0001 then fail "unexpected float"

let expect_rgba_hex expected color =
  equal string expected (Lib.Rgba.to_hex color)

let () =
  run "opentui-core-foundations"
    [
      test "rgba preserves channel values and terminal intent" (fun () ->
          let color = Lib.Rgba.from_values ~alpha:0.5 1.0 0.5 0.0 in
          let red, green, blue, alpha = Lib.Rgba.channels color in
          equal int 255 red;
          equal int 128 green;
          equal int 0 blue;
          equal int 128 alpha;
          equal bool true (match Lib.Rgba.intent color with Rgb -> true | Indexed | Default -> false);
          let indexed = expect_rgba (Lib.Rgba.from_index 21) in
          equal bool true (match Lib.Rgba.intent indexed with Indexed -> true | Rgb | Default -> false);
          equal int 21 (Option.get (Lib.Rgba.slot indexed));
          expect_rgba_hex "#0000ff" (expect_rgba (Lib.Rgba.of_hex "#0000ff"));
          expect_rgba_hex "#ff0000" (expect_rgba (Lib.Rgba.parse "red"));
          let converted = expect_native (Lib.Rgba.to_color color) in
          let converted_red, converted_green, converted_blue, converted_alpha =
            Core.Color.channels converted
          in
          equal int red converted_red;
          equal int green converted_green;
          equal int blue converted_blue;
          equal int alpha converted_alpha;
          expect_rgba_hex "#aabbcc" (expect_rgba (Lib.Rgba.of_hex "#abc"));
          expect_rgba_hex "#11223344" (expect_rgba (Lib.Rgba.of_hex "11223344"));
          equal int 0 (Lib.Rgba.alpha (expect_rgba (Lib.Rgba.parse "transparent")));
          expect_rgba_hex "#ff0000" (Lib.Rgba.hsv_to_rgb 0.0 1.0 1.0));
      test "terminal palette queries and chunked OSC responses" (fun () ->
          equal string "\027]4;0;?\007\027]4;1;?\007"
            (Lib.Terminal_palette.palette_query ~size:2 ());
          let tmux_query =
            Lib.Terminal_palette.wrap_for_legacy_tmux
              (Lib.Terminal_palette.osc_support_query ())
          in
          equal bool true (String.length tmux_query > 0);
          let parser = Lib.Terminal_palette.create ~size:4 () in
          Lib.Terminal_palette.feed parser "\027]4;1;#ff";
          Lib.Terminal_palette.feed parser
            "0000\007\027]10;#112233\007";
          equal bool true (Lib.Terminal_palette.complete parser);
          let colors = Lib.Terminal_palette.colors parser in
          equal string "#ff0000" (Option.get colors.palette.(1));
          equal string "#112233" (Option.get colors.default_foreground);
          let normalized = Lib.Terminal_palette.normalize (Some colors) in
          expect_rgba_hex "#ff0000" normalized.palette.(1);
          expect_rgba_hex "#112233" normalized.default_foreground;
          expect_rgba_hex "#000000" normalized.default_background);
      test "render geometry clamps split footer dimensions" (fun () ->
          let geometry =
            Lib.Render_geometry.calculate Lib.Render_geometry.Split_footer
              ~terminal_width:(-4) ~terminal_height:10 ~footer_height:3
          in
          equal int 3 geometry.effective_footer_height;
          equal int 7 geometry.render_offset;
          equal int 0 geometry.render_width;
          equal int 3 geometry.render_height;
          let full =
            Lib.Render_geometry.calculate Lib.Render_geometry.Main_screen
              ~terminal_width:8 ~terminal_height:4 ~footer_height:99
          in
          equal int 8 full.render_width;
          equal int 4 full.render_height;
          equal int 0 full.effective_footer_height);
      test "renderable validation keeps invalid dimensions structured" (fun () ->
          (match
             Lib.Renderable_validations.validate_options ~id:"panel"
               ~width:(Some 12.0) ~height:(Some 4.0)
           with
          | Ok () -> ()
          | Error _ -> fail "valid renderable dimensions were rejected");
          (match
             Lib.Renderable_validations.validate_options ~id:"panel"
               ~width:(Some (-1.0)) ~height:None
           with
          | Error (Lib.Renderable_validations.Invalid_number name) ->
              equal string "panel.width" name
          | Error _ -> fail "invalid width returned the wrong validation error"
          | Ok () -> fail "negative renderable width was accepted");
          (match Lib.Renderable_validations.padding "auto" with
          | Error (Lib.Renderable_validations.Invalid_value "padding:auto") -> ()
          | Error _ -> fail "padding:auto returned the wrong validation error"
          | Ok _ -> fail "padding:auto was accepted");
          (match Lib.Renderable_validations.position "25%" with
          | Ok (Lib.Renderable_validations.Percentage value) -> expect_float 25.0 value
          | Ok _ -> fail "percentage position was parsed incorrectly"
          | Error _ -> fail "percentage position was rejected"));
      test "portable utility owners keep clocks, queues, paths, and sinks explicit"
        (fun () ->
          let manual = Lib.Clock.manual () in
          let debounce = Lib.Debounce.create ~clock:(Lib.Clock.manual_clock manual) () in
          let callbacks = ref [] in
          Lib.Debounce.debounce debounce ~id:"syntax" ~delay:1.0
            (fun () -> callbacks := "old" :: !callbacks);
          Lib.Debounce.debounce debounce ~id:"syntax" ~delay:1.0
            (fun () -> callbacks := "new" :: !callbacks);
          Lib.Clock.advance manual 0.999;
          equal int 0 (List.length !callbacks);
          Lib.Clock.advance manual 0.001;
          equal string "new" (List.hd !callbacks);
          let scheduled = ref [] in
          let processed = ref [] in
          let queue =
            Lib.Queue.create
              ~schedule:(fun callback -> scheduled := callback :: !scheduled)
              ~process:(fun value -> processed := value :: !processed; Ok ())
              ~on_error:(fun _ -> fail "queue process unexpectedly failed") ()
          in
          Lib.Queue.enqueue queue 3;
          equal int 1 (Lib.Queue.size queue);
          (match !scheduled with
          | callback :: _ -> callback ()
          | [] -> fail "queue did not request its injected scheduler");
          equal int 0 (Lib.Queue.size queue);
          equal int 1 (List.length !processed);
          equal int 3 (List.hd !processed);
          let environment_value = ref (Some "42") in
          let environment = Lib.Env.create ~get:(fun _ -> !environment_value) () in
          let definition =
            { Lib.Env.name = "PORT"; description = "Listening port"; default = None;
              required = true; value_type = Lib.Env.Number }
          in
          (match Lib.Env.register environment definition with
          | Ok () -> ()
          | Error _ -> fail "environment definition was rejected");
          (match Lib.Env.value environment "PORT" with
          | Ok (Some (Lib.Env.Number value)) -> expect_float 42.0 value
          | Ok _ -> fail "environment number had the wrong value shape"
          | Error _ -> fail "environment number was not read");
          environment_value := Some "43";
          (match Lib.Env.value environment "PORT" with
          | Ok (Some (Lib.Env.Number value)) -> expect_float 42.0 value
          | Ok _ -> fail "environment cache changed before clear"
          | Error _ -> fail "cached environment number was not read");
          Lib.Env.clear_cache environment;
          (match Lib.Env.value environment "PORT" with
          | Ok (Some (Lib.Env.Number value)) -> expect_float 43.0 value
          | Ok _ -> fail "environment value after clear had the wrong shape"
          | Error _ -> fail "environment value after clear was not read");
          let data_paths =
            match
              Lib.Data_paths.create ~home:"/home/test" ~cwd:"/work"
                ~getenv:(fun key -> if String.equal key "XDG_CONFIG_HOME" then Some "/cfg" else None) ()
            with
            | Ok value -> value
            | Error error -> fail (Lib.Validate_dir_name.message error)
          in
          equal string "/cfg/opentui/init.ts" (Lib.Data_paths.paths data_paths).global_config_file;
          let path_notifications = ref 0 in
          let subscription =
            Lib.Data_paths.on_paths_changed data_paths (fun _ -> incr path_notifications)
          in
          (match Lib.Data_paths.set_app_name data_paths "demo" with
          | Ok () -> ()
          | Error error -> fail (Lib.Validate_dir_name.message error));
          equal int 1 !path_notifications;
          Core.Event_subscription.cancel subscription;
          (match Lib.Data_paths.set_app_name data_paths "next" with
          | Ok () -> ()
          | Error error -> fail (Lib.Validate_dir_name.message error));
          equal int 1 !path_notifications;
          let terminal_writes = ref [] in
          let disposed = ref false in
          let clipboard =
            Lib.Clipboard.create
              ~host:
                { max_write_bytes = 64;
                  read = (fun ~preferred_types:_ ~selection:_ -> Ok None);
                  write_text = (fun ~selection:_ _ -> Written);
                  clear = (fun ~selection:_ -> Cleared);
                  dispose = (fun () -> disposed := true) }
              ~terminal:
                { remote = false; capability = Supported;
                  write = (fun bytes -> terminal_writes := bytes :: !terminal_writes; Ok ()) }
              ()
          in
          (match
             Lib.Clipboard.write_text clipboard ~destination:Lib.Clipboard.Terminal_only
               "hello"
           with
          | Ok (Lib.Clipboard.Not_attempted, Lib.Clipboard.Attempted) -> ()
          | Ok _ -> fail "terminal-only clipboard write used the wrong status"
          | Error error -> fail (Lib.Clipboard.message error));
          equal string "\027]52;c;aGVsbG8=\007"
            (Bytes.to_string (List.hd !terminal_writes));
          (match
             Lib.Clipboard.write_text clipboard ~destination:Lib.Clipboard.Host_only
               "hello"
           with
          | Ok (Lib.Clipboard.Written, Lib.Clipboard.Not_attempted) -> ()
          | Ok _ -> fail "host-only clipboard write used the wrong status"
          | Error error -> fail (Lib.Clipboard.message error));
          Lib.Clipboard.dispose clipboard;
          equal bool true !disposed;
          (match
             Lib.Clipboard.write_text clipboard ~destination:Lib.Clipboard.Host_only
               "hello"
           with
          | Error Lib.Clipboard.Disposed -> ()
          | Error error -> fail (Lib.Clipboard.message error)
          | Ok _ -> fail "disposed clipboard accepted a write");
          let capture = Lib.Output_capture.create ~max_bytes:4 () in
          ignore
            (match Lib.Output_capture.write capture ~stream:Lib.Output_capture.Stdout "ab" with
            | Ok () -> Ok ()
            | Error _ -> fail "capture rejected a bounded write");
          equal int 2 (Lib.Output_capture.bytes capture);
          equal string "ab" (Lib.Output_capture.claim_output capture);
          equal int 0 (Lib.Output_capture.bytes capture);
          (match Lib.Output_capture.write capture ~stream:Lib.Output_capture.Stderr "abcde" with
          | Error Lib.Output_capture.Limit_exceeded -> ()
          | Error _ -> fail "capture returned the wrong limit error"
          | Ok () -> fail "capture exceeded its configured byte limit");
          Lib.Output_capture.close capture;
          (match Lib.Output_capture.write capture ~stream:Lib.Output_capture.Stdout "x" with
          | Error Lib.Output_capture.Closed -> ()
          | Error _ -> fail "closed capture returned the wrong error"
          | Ok () -> fail "closed capture accepted output");
          equal string "\027[2C" (match Lib.Ansi.cursor_move ~row:0 ~column:2 with Ok value -> value | Error _ -> "");
          (match Lib.Yoga_options.parse_wrap "WRAP-REVERSE" with
          | Ok Core.Yoga.Wrap_reverse -> ()
          | Ok _ -> fail "Yoga option selected the wrong wrap mode"
          | Error _ -> fail "Yoga option parser rejected case-insensitive input"));
      test "renderer theme mode owns query timing and waiter completion" (fun () ->
          let manual = Lib.Clock.manual () in
          let queries = ref 0 in
          let theme =
            Core.Renderer_theme_mode.create
              ~clock:(Lib.Clock.manual_clock manual)
              ~query:(fun () -> incr queries) ()
          in
          let result = ref None in
          let waiter =
            Core.Renderer_theme_mode.wait_for theme ~timeout_ms:100
              ~on_result:(fun mode -> result := Some mode)
          in
          ignore waiter;
          equal string "\027]10;?\007\027]11;?\007"
            Core.Renderer_theme_mode.query_sequence;
          let request =
            Core.Renderer_theme_mode.handle_sequence theme "\027[?997;1n"
          in
          equal bool true request.handled;
          equal int 1 !queries;
          let response =
            Core.Renderer_theme_mode.handle_sequence theme
              "\027]10;#000000\007\027]11;#ffffff\007"
          in
          (match response.changed_mode with
          | Some Core.Renderer_theme_mode.Light -> ()
          | Some Core.Renderer_theme_mode.Dark -> fail "theme mode inferred as dark"
          | None -> fail "theme response did not change the mode");
          (match !result with
          | Some (Some Core.Renderer_theme_mode.Light) -> ()
          | Some (Some Core.Renderer_theme_mode.Dark) -> fail "waiter received dark mode"
          | Some None -> fail "waiter received no theme mode"
          | None -> fail "theme waiter was not completed");
          Core.Renderer_theme_mode.cancel_wait theme waiter);
      test "theme disposal cancels waiters before user callbacks" (fun () ->
          let manual = Lib.Clock.manual () in
          let theme =
            Core.Renderer_theme_mode.create
              ~clock:(Lib.Clock.manual_clock manual) ~query:(fun () -> ()) ()
          in
          let callback_calls = ref 0 in
          let waiter =
            Core.Renderer_theme_mode.wait_for theme ~timeout_ms:100
              ~on_result:(fun _ ->
                incr callback_calls;
                raise (Failure "disposed theme waiter was invoked"))
          in
          Core.Renderer_theme_mode.dispose theme;
          equal int 0 !callback_calls;
          let reentrant_calls = ref 0 in
          let reentrant_waiter =
            Core.Renderer_theme_mode.wait_for theme ~timeout_ms:0
              ~on_result:(fun _ -> incr reentrant_calls)
          in
          equal int 0 !reentrant_calls;
          Core.Renderer_theme_mode.cancel_wait theme waiter;
          Core.Renderer_theme_mode.cancel_wait theme reentrant_waiter);
      test "viewport culling retains overlap and orders by z" (fun () ->
          let viewport : Lib.Objects_in_viewport.viewport =
            { x = 0.0; y = 0.0; width = 10.0; height = 4.0 }
          in
          let objects =
            [
              { Lib.Objects_in_viewport.value = "back"; screen_x = 1.0; screen_y = 1.0; width = 2.0; height = 1.0; z_index = 10 };
              { value = "front"; screen_x = 2.0; screen_y = 1.0; width = 2.0; height = 1.0; z_index = 1 };
              { value = "outside"; screen_x = 30.0; screen_y = 30.0; width = 1.0; height = 1.0; z_index = 0 };
            ]
          in
          let visible = Lib.Objects_in_viewport.get ~padding:0.0 ~min_trigger_size:16 viewport objects in
          equal int 2 (List.length visible);
          equal string "front" (List.hd visible).value;
          equal string "back" (List.hd (List.tl visible)).value);
      test "selection aggregates selected text by terminal position" (fun () ->
          let selection =
            Lib.Selection.create
              ~anchor:{ Lib.Selection.x = 4.0; y = 2.0 }
              ~focus:{ x = 0.0; y = 0.0 }
          in
          Lib.Selection.update_selected_renderables selection
            [
              { id = 2; x = 2.0; y = 1.0; destroyed = false; text = "B" };
              { id = 1; x = 0.0; y = 0.0; destroyed = false; text = "A" };
              { id = 3; x = 0.0; y = 0.0; destroyed = true; text = "ignored" };
            ];
          equal string "A\nB" (Lib.Selection.selected_text selection);
          let local =
            Option.get
              (Lib.Selection.convert_global_to_local (Some selection) ~local_x:1.0
                 ~local_y:2.0)
          in
          expect_float 3.0 local.anchor_x;
          expect_float 0.0 local.anchor_y;
          expect_float (-1.0) local.focus_x;
          expect_float (-2.0) local.focus_y);
      test "styled text and syntax styles compose attributes" (fun () ->
          let bold = Lib.Styled_text.bold (Lib.Styled_text.Text "hello") in
          equal string "hello" bold.text;
          equal bool true (bold.attributes land Lib.Text_attributes.bold <> 0);
          let style = Core.Syntax_style.create () in
          let base =
            {
              Core.Syntax_style.fg = Some (Lib.Rgba.from_ints 255 0 0);
              bg = None;
              bold = Some true;
              italic = None;
              underline = None;
              dim = None;
            }
          in
          let nested =
            { base with Core.Syntax_style.fg = None; italic = Some true }
          in
          ignore (Core.Syntax_style.register_style style "keyword" base);
          ignore (Core.Syntax_style.register_style style "keyword.operator" nested);
          expect_int_option (Some 1) (Core.Syntax_style.get_style_id style "keyword.operator");
          let merged = Core.Syntax_style.merge_styles style [ "keyword"; "keyword.operator" ] in
          equal bool true (Option.is_some merged.fg);
          equal bool true (merged.attributes land Lib.Text_attributes.bold <> 0);
          equal bool true (merged.attributes land Lib.Text_attributes.italic <> 0);
          equal int 1 (Core.Syntax_style.cache_size style);
          Core.Syntax_style.destroy style);
      test "edit buffer tracks cursor history and extmarks" (fun () ->
          let buffer = Core.Edit_buffer.create Core.Edit_buffer.Unicode in
          equal int 1 (expect_ok (Core.Edit_buffer.line_count buffer));
          ignore (expect_ok (Core.Edit_buffer.set_text buffer "abcd"));
          equal int 1 (expect_ok (Core.Edit_buffer.line_count buffer));
          let marks = expect_ok (Core.Edit_buffer.extmarks buffer) in
          let id =
            expect_ok
              (Lib.Extmarks.create_mark marks
                 {
                   start = 2;
                   end_ = 3;
                   virtual_ = false;
                   style_id = None;
                   priority = None;
                   data = Some "mark";
                   type_id = None;
                   metadata = None;
                 })
          in
          ignore (expect_ok (Core.Edit_buffer.set_cursor_by_offset buffer 0));
          ignore (expect_ok (Core.Edit_buffer.insert_char buffer "X"));
          equal string "Xabcd" (expect_ok (Core.Edit_buffer.text buffer));
          equal int 3
            (Option.get
               (Option.map (fun (mark : Lib.Extmarks.extmark) -> mark.start)
                  (expect_ok (Lib.Extmarks.get marks id))));
          ignore (expect_ok (Core.Edit_buffer.undo buffer));
          equal string "abcd" (expect_ok (Core.Edit_buffer.text buffer));
          equal int 2
            (Option.get
               (Option.map (fun (mark : Lib.Extmarks.extmark) -> mark.start)
                  (expect_ok (Lib.Extmarks.get marks id))));
          ignore (expect_ok (Core.Edit_buffer.redo buffer));
          equal string "Xabcd" (expect_ok (Core.Edit_buffer.text buffer));
          Core.Edit_buffer.destroy buffer);
      test "editor word boundaries preserve native delimiter and mixed-script rules"
        (fun () ->
          let buffer = Core.Edit_buffer.create Core.Edit_buffer.Unicode in
          ignore (expect_ok (Core.Edit_buffer.set_text buffer "Hello World"));
          ignore
            (expect_ok
               (Core.Edit_buffer.set_cursor_to_line_col buffer ~line:0 ~col:0));
          equal int 6
            (expect_ok (Core.Edit_buffer.next_word_boundary buffer)).col;
          ignore
            (expect_ok
               (Core.Edit_buffer.set_cursor_to_line_col buffer ~line:0 ~col:7));
          equal int 6
            (expect_ok (Core.Edit_buffer.previous_word_boundary buffer)).col;
          ignore (expect_ok (Core.Edit_buffer.set_text buffer "日本語abc"));
          ignore
            (expect_ok
               (Core.Edit_buffer.set_cursor_to_line_col buffer ~line:0 ~col:0));
          equal int 6
            (expect_ok (Core.Edit_buffer.next_word_boundary buffer)).col;
          ignore
            (expect_ok
               (Core.Edit_buffer.set_cursor_to_line_col buffer ~line:0 ~col:9));
          equal int 6
            (expect_ok (Core.Edit_buffer.previous_word_boundary buffer)).col;
          ignore (expect_ok (Core.Edit_buffer.set_text buffer "Hello\tWorld"));
          ignore
            (expect_ok
               (Core.Edit_buffer.set_cursor_to_line_col buffer ~line:0 ~col:0));
          equal int 7
            (expect_ok (Core.Edit_buffer.next_word_boundary buffer)).col;
          ignore
            (expect_ok
               (Core.Edit_buffer.set_cursor_to_line_col buffer ~line:0 ~col:12));
          equal int 7
            (expect_ok (Core.Edit_buffer.previous_word_boundary buffer)).col;
          Core.Edit_buffer.destroy buffer);
      test "editor offsets keep combining marks and joined emoji intact"
        (fun () ->
          let combining = Core.Edit_buffer.create Core.Edit_buffer.Unicode in
          ignore (expect_ok (Core.Edit_buffer.set_text combining "e\u{301}X"));
          equal string "e\u{301}"
            (expect_ok
               (Core.Edit_buffer.text_range combining ~start_offset:0
                  ~end_offset:1));
          ignore (expect_ok (Core.Edit_buffer.set_cursor_by_offset combining 0));
          ignore (expect_ok (Core.Edit_buffer.move_cursor_right combining));
          equal int 1 (expect_ok (Core.Edit_buffer.cursor combining)).offset;
          ignore (expect_ok (Core.Edit_buffer.move_cursor_right combining));
          equal int 2 (expect_ok (Core.Edit_buffer.cursor combining)).offset;
          Core.Edit_buffer.destroy combining;
          let joined = Core.Edit_buffer.create Core.Edit_buffer.Unicode in
          ignore (expect_ok (Core.Edit_buffer.set_text joined "👩‍💻X"));
          equal string "👩‍💻"
            (expect_ok
               (Core.Edit_buffer.text_range joined ~start_offset:0
                  ~end_offset:2));
          ignore (expect_ok (Core.Edit_buffer.set_cursor_by_offset joined 0));
          ignore (expect_ok (Core.Edit_buffer.move_cursor_right joined));
          equal int 2 (expect_ok (Core.Edit_buffer.cursor joined)).offset;
          ignore (expect_ok (Core.Edit_buffer.move_cursor_right joined));
          equal int 3 (expect_ok (Core.Edit_buffer.cursor joined)).offset;
          Core.Edit_buffer.destroy joined);
      test "editor view wraps and exposes the edit-buffer extmark owner" (fun () ->
          let buffer = Core.Edit_buffer.create Core.Edit_buffer.Unicode in
          ignore (expect_ok (Core.Edit_buffer.set_text buffer "abcdef"));
          let view = Core.Editor_view.create buffer ~viewport_width:3 ~viewport_height:2 in
          Core.Editor_view.set_wrap_mode view Core.Editor_view.Char;
          let info = Core.Editor_view.line_info view in
          expect_int_array [| 3; 3 |] info.line_width_cols;
          equal int 2 (Core.Editor_view.virtual_line_count view);
          ignore (expect_ok (Core.Editor_view.set_cursor_by_offset view 2));
          Core.Editor_view.set_selection view ~start:1 ~end_:4;
          equal string "bcd" (expect_ok (Core.Editor_view.selected_text view));
          let extmarks = expect_ok (Core.Editor_view.extmarks view) in
          equal int 0 (List.length (expect_ok (Lib.Extmarks.all extmarks)));
          Core.Editor_view.destroy view;
          Core.Edit_buffer.destroy buffer);
      test "text buffers preserve native line-count and file-loading semantics" (fun () ->
          let buffer = expect_ok (Core.Text_buffer.create Core.Text_buffer.Unicode) in
          equal int 1 (expect_ok (Core.Text_buffer.line_count buffer));
          ignore (expect_ok (Core.Text_buffer.set_text buffer "first\nsecond"));
          equal int 2 (expect_ok (Core.Text_buffer.line_count buffer));
          ignore (expect_ok (Core.Text_buffer.clear buffer));
          ignore (expect_ok (Core.Text_buffer.append buffer "first\r\nsecond"));
          equal string "first\nsecond" (expect_ok (Core.Text_buffer.text buffer));
          let path = Filename.temp_file "opentui-text-buffer" ".txt" in
          Fun.protect
            (fun () ->
              Out_channel.with_open_bin path (fun channel ->
                  output_string channel "loaded\ncontent");
              ignore (expect_ok (Core.Text_buffer.load_file buffer ~path));
              equal string "loaded\ncontent" (expect_ok (Core.Text_buffer.text buffer));
              equal int 2 (expect_ok (Core.Text_buffer.line_count buffer));
              ignore (expect_ok (Core.Text_buffer.close buffer)))
            ~finally:(fun () -> Sys.remove path));
      test "native text metadata and view selection stay available" (fun () ->
          let buffer = expect_ok (Core.Text_buffer.create Core.Text_buffer.Unicode) in
          let styled =
            Lib.Styled_text.create
              [
                Lib.Styled_text.chunk ~attributes:Lib.Text_attributes.bold "ab";
                Lib.Styled_text.chunk "cd";
              ]
          in
          ignore (expect_ok (Core.Text_buffer.set_styled_text buffer styled));
          equal string "abcd" (expect_ok (Core.Text_buffer.text buffer));
          equal int 2 (List.length (Lib.Styled_text.chunks (Option.get (expect_ok (Core.Text_buffer.styled_text buffer)))));
          ignore (expect_ok (Core.Text_buffer.set_tab_width buffer 1));
          equal int 2 (expect_ok (Core.Text_buffer.tab_width buffer));
          ignore (expect_ok (Core.Text_buffer.set_tab_width buffer 8));
          equal int 8 (expect_ok (Core.Text_buffer.tab_width buffer));
          ignore
            (expect_ok
               (Core.Text_buffer.add_highlight buffer ~line:0
                  { start = 0; end_ = 2; style_id = 4; priority = Some 1; hl_ref = Some 7 }));
          equal int 1 (expect_ok (Core.Text_buffer.highlight_count buffer));
          equal int 1 (List.length (expect_ok (Core.Text_buffer.line_highlights buffer 0)));
          let view = expect_ok (Core.Text_buffer_view.create buffer) in
          ignore (expect_ok (Core.Text_buffer_view.set_selection view ~start:1 ~end_:3 ()));
          let selection = expect_ok (Core.Text_buffer_view.selection view) in
          equal int 1 (Option.get selection).start;
          equal int 3 (Option.get selection).end_;
          equal string "bc" (expect_ok (Core.Text_buffer_view.selected_text view));
          ignore (expect_ok (Core.Text_buffer_view.reset_selection view));
          ignore
            (expect_ok
               (Core.Text_buffer_view.set_local_selection view ~anchor_x:0 ~anchor_y:0
                  ~focus_x:2 ~focus_y:0 ()));
          equal string "ab" (expect_ok (Core.Text_buffer_view.selected_text view));
          ignore (expect_ok (Core.Text_buffer_view.close view));
          ignore (expect_ok (Core.Text_buffer.close buffer)));
      test "core native span feed preserves ownership boundaries" (fun () ->
          let feed = expect_ok (Core.Native_span_feed.create ()) in
          ignore (expect_ok (Core.Native_span_feed.write feed (Bytes.of_string "hello")));
          ignore (expect_ok (Core.Native_span_feed.commit feed));
          let stats = expect_ok (Core.Native_span_feed.stats feed) in
          equal int64 5L stats.bytes_written;
          equal int64 1L stats.spans_committed;
          let spans = expect_ok (Core.Native_span_feed.drain feed) in
          equal int 1 (List.length spans);
          equal string "hello" (Bytes.to_string (Core.Native_span_feed.Span.bytes (List.hd spans)));
          ignore (expect_ok (Core.Native_span_feed.Span.release (List.hd spans)));
          ignore (expect_ok (Core.Native_span_feed.close feed));
          match Core.Native_span_feed.stats feed with
          | Error Core.Error.Closed -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok _ -> fail "closed span feed returned statistics");
      test "slider owns value changes and renders through the retained tree" (fun () ->
          let renderer = expect_ok (Core.Renderer.create ~width:8l ~height:2l) in
          let slider =
            expect_ok
              (Core.Renderables.Slider.create (Core.Renderer.context renderer)
                 ~orientation:Core.Renderables.Slider.Horizontal ~min:0.0 ~max:10.0
                 ~value:2.0 ~viewport_size:2.0 ~width:(Core.Yoga.Point 5.0)
                 ~height:(Core.Yoga.Point 1.0) ())
          in
          let changes = ref [] in
          ignore
            (Core.Renderables.Slider.on_change slider (fun value -> changes := value :: !changes));
          ignore
            (expect_ok
               (Core.Layout_children.add (Core.Renderer.children renderer)
                  (Core.Renderables.Slider.as_renderable slider)));
          ignore (expect_ok (Core.Renderer.render renderer ~force:true));
          ignore (expect_ok (Core.Renderables.Slider.set_value slider 7.0));
          expect_float 7.0 (Core.Renderables.Slider.value slider);
          equal int 1 (List.length !changes);
          Core.Renderables.Slider.destroy slider;
          (match Core.Renderables.Slider.set_value slider 3.0 with
          | Error Core.Error.Destroyed -> ()
          | Error error -> fail (Core.Error.message error)
          | Ok () -> fail "destroyed slider accepted a value");
          Core.Renderer.destroy renderer);
      test "renderer exposes palette and split-footer geometry" (fun () ->
          let renderer = expect_ok (Core.Renderer.create ~width:8l ~height:4l) in
          equal string "\027[14t" (Core.Renderer.pixel_resolution_query renderer);
          equal string "\027]4;0;?\007" (Core.Renderer.palette_query renderer ~size:1 ());
          let events = ref 0 in
          ignore (expect_ok (Core.Renderer.on_palette renderer (fun _ -> incr events)));
          equal bool true
            (expect_ok
               (Core.Renderer.feed_palette_response renderer
                  "\027]4;0;#010203\007\027]10;#ffffff\007"));
          equal int 1 !events;
          let palette = Option.get (expect_ok (Core.Renderer.palette renderer)) in
          expect_rgba_hex "#010203" palette.palette.(0);
          ignore
            (expect_ok
               (Core.Renderer.set_render_geometry renderer
                  Lib.Render_geometry.Split_footer ~footer_height:1));
          let geometry = expect_ok (Core.Renderer.render_geometry renderer) in
          equal int 1 geometry.render_height;
          equal int 3 geometry.render_offset;
          Core.Renderer.destroy renderer);
    ]
