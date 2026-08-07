open Windtrap

module Modes = Opentui_terminal.Terminal_modes

let output transition = Bytes.to_string (Modes.output transition)

let expect_screen expected actual =
  match expected, actual with
  | Modes.Main, Modes.Main | Modes.Alternate, Modes.Alternate -> ()
  | _ -> fail "unexpected terminal screen state"

let expect_mouse_mode expected actual =
  match expected, actual with
  | Modes.Disabled, Modes.Disabled
  | Modes.Buttons, Modes.Buttons
  | Modes.Motion, Modes.Motion -> ()
  | _ -> fail "unexpected terminal mouse mode"

let () =
  run "opentui-terminal-modes"
    [
      test "transitions are immutable until their next state is selected" (fun () ->
          let initial = Modes.initial in
          let transition = Modes.set_screen initial Modes.Alternate in
          expect_screen Modes.Main (Modes.screen initial);
          equal string "\x1b[?1049h" (output transition);
          expect_screen Modes.Alternate (Modes.screen (Modes.next transition)));
      test "screen and cursor transitions are idempotent" (fun () ->
          let alternate = Modes.next (Modes.set_screen Modes.initial Modes.Alternate) in
          equal string "" (output (Modes.set_screen alternate Modes.Alternate));
          let hidden = Modes.next (Modes.set_cursor_visible Modes.initial false) in
          equal bool false (Modes.cursor_visible hidden);
          equal string "" (output (Modes.set_cursor_visible hidden false));
          let visible = Modes.next (Modes.set_cursor_visible hidden true) in
          equal bool true (Modes.cursor_visible visible);
          equal string "\x1b[?25h"
            (output (Modes.set_cursor_visible hidden true)));
      test "mouse transitions match pinned tracking order" (fun () ->
          let buttons = Modes.set_mouse Modes.initial ~movement:false in
          equal string
            "\x1b[?1003l\x1b[?1000h\x1b[?1002h\x1b[?1006h"
            (output buttons);
          expect_mouse_mode Modes.Buttons (Modes.mouse_mode (Modes.next buttons));
          let motion = Modes.set_mouse (Modes.next buttons) ~movement:true in
          equal string "\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h"
            (output motion);
          expect_mouse_mode Modes.Motion (Modes.mouse_mode (Modes.next motion));
          let buttons_again =
            Modes.set_mouse (Modes.next motion) ~movement:false
          in
          equal string
            "\x1b[?1003l\x1b[?1000h\x1b[?1002h\x1b[?1006h"
            (output buttons_again);
          expect_mouse_mode Modes.Buttons
            (Modes.mouse_mode (Modes.next buttons_again));
          let disabled = Modes.disable_mouse (Modes.next motion) in
          equal string
            "\x1b[?1003l\x1b[?1002l\x1b[?1000l\x1b[?1006l"
            (output disabled);
          expect_mouse_mode Modes.Disabled
            (Modes.mouse_mode (Modes.next disabled)));
      test "bracketed paste is idempotent" (fun () ->
          let enabled = Modes.set_bracketed_paste Modes.initial true in
          equal string "\x1b[?2004h" (output enabled);
          let state = Modes.next enabled in
          equal bool true (Modes.bracketed_paste state);
          equal string "" (output (Modes.set_bracketed_paste state true));
          equal string "\x1b[?2004l"
            (output (Modes.set_bracketed_paste state false)));
      test "reset restores owned modes in cleanup order" (fun () ->
          let state =
            Modes.next (Modes.set_screen Modes.initial Modes.Alternate)
          in
          let state = Modes.next (Modes.set_cursor_visible state false) in
          let state = Modes.next (Modes.set_mouse state ~movement:true) in
          let state = Modes.next (Modes.set_bracketed_paste state true) in
          let transition = Modes.reset state in
          equal string
            "\x1b[?25h\x1b[0m\x1b[?1003l\x1b[?1002l\x1b[?1000l\x1b[?1006l\x1b[?2004l\x1b[?1049l"
            (output transition);
          expect_screen Modes.Main (Modes.screen (Modes.next transition));
          equal bool true (Modes.cursor_visible (Modes.next transition));
          expect_mouse_mode Modes.Disabled
            (Modes.mouse_mode (Modes.next transition));
          equal bool false
            (Modes.bracketed_paste (Modes.next transition)));
      test "disabled mouse retains force-cleanup history" (fun () ->
          let enabled = Modes.next (Modes.set_mouse Modes.initial ~movement:true) in
          let disabled = Modes.next (Modes.disable_mouse enabled) in
          equal string "" (output (Modes.disable_mouse disabled));
          equal string
            "\x1b[0m\x1b[?1003l\x1b[?1002l\x1b[?1000l\x1b[?1006l"
            (output (Modes.reset disabled)))
    ]
