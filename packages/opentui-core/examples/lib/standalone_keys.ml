(* Port of vendor/opentui/packages/examples/src/lib/standalone-keys.ts.

   Demo-wide keyboard conveniences. The reference binds a handful of debug
   controls (debug overlay, hit-grid dump, renderer start/stop/auto, and a
   native arena-allocation readout). The OCaml renderer is always explicit-frame
   and does not yet expose a debug overlay, a hit-grid dump, or native arena
   introspection, so those bindings are intentionally omitted and noted below. *)

module O = Opentui_core
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler

(* Reference keys not yet implemented in the OCaml port:
   - `.` toggles the debug overlay ([toggleDebugOverlay]).
   - [g]+Ctrl dumps the committed hit grid ([dumpHitGrid]).
   - [l]+Shift starts continuous rendering ([renderer.start]); [s]+Shift stops
     it; [a]+Shift switches to auto. The OCaml renderer renders on demand with
     explicit [request_render]/live-lease controls.
   - [a]+Ctrl prints native arena-allocated bytes ([getArenaAllocatedBytes]),
     which the OCaml port has not bound. *)

let setup_common_demo_keys renderer ~on_ctrl_c =
  ignore
    (O.Renderer.on_keypress renderer (fun key_event ->
         if Handler.key_event_kind key_event = Handler.Keypress then begin
           let modifiers = Handler.key_modifiers key_event in
           match Handler.key key_event with
           | Key.Character bytes when not modifiers.ctrl ->
               let raw = Bytes.to_string bytes in
               if String.equal raw "`" || String.equal raw "\"" then
                 ignore (O.Console.toggle (O.Renderer.console renderer))
           | Key.Character bytes when modifiers.ctrl ->
               (* Ctrl+C arrives in raw mode either as a literal ETX byte
                  (decoded as Character "c" with ctrl set) or as a Kitty
                  frame for the same key. *)
               if Bytes.equal bytes (Bytes.of_string "c")
                  || Bytes.equal bytes (Bytes.of_string "\003")
               then on_ctrl_c ()
           | Key.Named _ | Key.Character _ -> ()
         end))