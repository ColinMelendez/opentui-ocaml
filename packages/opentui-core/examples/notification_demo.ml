(* Port of vendor/opentui/packages/examples/src/notification-demo.ts.

   Demonstrates terminal notifications through the native renderer's detected
   OSC transport, including title/body messages, delayed work, capability
   status, mouse cards, and a bounded activity log. *)

module O = Opentui_core
module S = O.Lib.Styled_text
module A = O.Lib.Text_attributes
module Util = Opentui_examples_lib.Util
module Box = O.Renderables.Box
module Text = O.Renderables.Text
module Scroll_box = O.Renderables.Scroll_box
module Scroll_bar = O.Renderables.Scroll_bar
module Key = O.Lib.Key_decoder
module Handler = O.Lib.Key_handler
module Clock = O.Lib.Clock
module Capabilities = O.Terminal_capabilities

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let color = Util.color_of_hex

module Palette = struct
  let bg = color "#08111f"
  let panel = color "#0f1b2d"
  let panel_alt = color "#111f34"
  let border = color "#223553"
  let border_hot = color "#22d3ee"
  let text = color "#d7e3f7"
  let muted = color "#7d8da8"
  let cyan = color "#22d3ee"
  let violet = color "#a78bfa"
  let lime = color "#bef264"
  let rose = color "#fb7185"
  let amber = color "#fbbf24"
  let blue = color "#60a5fa"
  let hover = color "#172845"
  let pressed = color "#20365b"
end

type notification_action = {
  key : string;
  title : string;
  subtitle : string;
  accent : O.Color.t;
  message : string;
  notification_title : string option;
  delayed : bool;
}

let actions =
  [|
    {
      key = "1";
      title = "Quick ping";
      subtitle = "Body-only notification";
      accent = Palette.cyan;
      message = "OpenTUI notification ping delivered.";
      notification_title = None;
      delayed = false;
    };
    {
      key = "2";
      title = "Build complete";
      subtitle = "Title and body";
      accent = Palette.lime;
      message = "The example build finished successfully.";
      notification_title = Some "OpenTUI build";
      delayed = false;
    };
    {
      key = "3";
      title = "Async task";
      subtitle = "Waits, then notifies";
      accent = Palette.violet;
      message = "The simulated background task is complete.";
      notification_title = Some "Background task finished";
      delayed = true;
    };
    {
      key = "4";
      title = "Needs attention";
      subtitle = "Prompt-style alert";
      accent = Palette.rose;
      message = "A task is waiting for your input in the terminal.";
      notification_title = Some "Action required";
      delayed = false;
    };
  |]

type notification_card = {
  box : Box.t;
  mutable hovered : bool;
}

type demo = {
  renderer : O.Renderer.t;
  root : Box.t;
  status : Text.t;
  log_list : Scroll_box.t;
  clock : Clock.t;
  exit : unit -> unit;
  mutable cards : notification_card array;
  mutable log_rows : Text.t list;
  mutable log_entry_id : int;
  mutable pending_timer : Clock.timer option;
  mutable pending_generation : int;
  mutable live_lease : O.Renderer.live_lease option;
  mutable key_subscription : O.Event_subscription.t option;
  mutable capability_subscription : O.Event_subscription.t option;
  mutable destroyed : bool;
}

let styled ?(attributes = A.none) ?fg text = S.chunk ?fg ~attributes text
let content chunks = S.create chunks

let make_text context ?id styled_content =
  expect_ok (Text.create context ?id ~content:styled_content ())

let add_child children renderable =
  ignore (expect_ok (O.Layout_children.add children renderable))

let set_renderable renderable setter = ignore (expect_ok (setter renderable))

let set_dimensions renderable ~width ~height =
  set_renderable renderable (fun value -> O.Renderable.set_width value width);
  set_renderable renderable (fun value -> O.Renderable.set_height value height)

let update_card_colors card ~background ~border =
  ignore (expect_ok (Box.set_background_color card.box background));
  ignore (expect_ok (Box.set_border_color card.box border))

let update_card_background card background =
  ignore (expect_ok (Box.set_background_color card.box background))

let current_capabilities demo = expect_ok (O.Renderer.capabilities demo.renderer)

let update_status demo capabilities =
  let supported =
    match capabilities with
    | Some value -> value.Capabilities.notifications
    | None -> false
  in
  let terminal_name, terminal_version =
    match capabilities with
    | None -> "detecting", ""
    | Some value ->
        let name = value.Capabilities.terminal.name in
        (if String.equal name "" then "detecting" else name),
        value.Capabilities.terminal.version
  in
  let transport, transport_color =
    match capabilities with
    | Some value -> (
        match value.Capabilities.multiplexer with
        | Capabilities.Tmux -> "tmux passthrough", Palette.amber
        | Capabilities.Zellij -> "Zellij OSC 99", Palette.amber
        | Capabilities.No_multiplexer
        | Capabilities.Screen
        | Capabilities.Unknown_multiplexer -> "direct OSC", Palette.blue)
    | None -> "direct OSC", Palette.blue
  in
  let terminal =
    if String.equal terminal_version "" then terminal_name
    else terminal_name ^ " " ^ terminal_version
  in
  let status_content =
    content
      [
        styled ~attributes:A.bold ~fg:Palette.text "Terminal notifications";
        styled ~fg:Palette.text ": ";
        styled ~fg:(if supported then Palette.lime else Palette.rose)
          (if supported then "enabled" else "not detected");
        styled "\n";
        styled ~fg:Palette.muted "Terminal: ";
        styled ~fg:Palette.cyan terminal;
        styled ~fg:Palette.muted "  Transport: ";
        styled ~fg:transport_color transport;
      ]
  in
  ignore (expect_ok (Text.set_content demo.status status_content))

let timestamp () =
  let time = Unix.localtime (Unix.gettimeofday ()) in
  Printf.sprintf "%02d:%02d:%02d" time.Unix.tm_hour time.Unix.tm_min
    time.Unix.tm_sec

let add_log demo message foreground =
  let row =
    make_text (O.Renderer.context demo.renderer)
      ~id:(Printf.sprintf "notification-demo-log-entry-%d" demo.log_entry_id)
      (content [ styled ~fg:foreground (timestamp () ^ "  " ^ message) ])
  in
  set_renderable (Text.as_renderable row) (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable (Text.as_renderable row) (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  demo.log_entry_id <- demo.log_entry_id + 1;
  ignore (expect_ok (Scroll_box.add demo.log_list (Text.as_renderable row)));
  demo.log_rows <- demo.log_rows @ [ row ];
  while Int.compare (List.length demo.log_rows) 80 > 0 do
    match demo.log_rows with
    | [] -> ()
    | old_row :: remaining ->
        demo.log_rows <- remaining;
        O.Renderable.destroy_recursively (Text.as_renderable old_row)
  done

let cancel_pending_timer demo =
  match demo.pending_timer with
  | None -> ()
  | Some timer ->
      Clock.cancel demo.clock timer;
      demo.pending_timer <- None;
      demo.pending_generation <- demo.pending_generation + 1

let send_notification demo action =
  let result =
    match action.notification_title with
    | None ->
        O.Renderer.trigger_notification demo.renderer ~message:action.message ()
    | Some title ->
        O.Renderer.trigger_notification demo.renderer ~message:action.message
          ~title ()
  in
  let sent = expect_ok result in
  add_log demo
    (if sent then "Sent: " ^ action.title
     else "Not sent: " ^ action.title ^ " (unsupported)")
    (if sent then action.accent else Palette.rose);
  update_status demo (current_capabilities demo)

let trigger_action demo action =
  if action.delayed then begin
    cancel_pending_timer demo;
    add_log demo "Started simulated background task..." action.accent;
    let generation = demo.pending_generation in
    let timer =
      Clock.schedule demo.clock ~delay:1.4 (fun () ->
          if not demo.destroyed && Int.equal generation demo.pending_generation then begin
            demo.pending_timer <- None;
            send_notification demo action
          end)
    in
    demo.pending_timer <- Some timer
  end
  else send_notification demo action

let create_card demo context action =
  let box =
    expect_ok
      (Box.create context
         ~id:("notification-card-" ^ action.key)
         ~background_color:Palette.panel_alt
         ~border_style:O.Lib.Border.Rounded ~border:Box.all_borders
         ~border_color:Palette.border ~title:(" " ^ action.key ^ " ")
         ~title_alignment:O.Lib.Border.Left ())
  in
  let renderable = Box.as_renderable box in
  set_dimensions renderable ~width:O.Yoga.Auto ~height:(O.Yoga.Point 9.0);
  set_renderable renderable (fun value ->
      O.Renderable.set_min_width value (O.Yoga.Point 18.0));
  set_renderable renderable (fun value -> O.Renderable.set_flex_grow value (Some 1.0));
  set_renderable renderable (fun value ->
      O.Renderable.set_flex_shrink value (Some 1.0));
  set_renderable renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_column);
  set_renderable renderable (fun value ->
      O.Renderable.set_padding value ~edge:O.Yoga.All (O.Yoga.Point 1.0));
  set_renderable renderable (fun value ->
      O.Renderable.set_margin value ~edge:O.Yoga.Right (O.Yoga.Point 1.0));
  ignore (expect_ok (Box.set_z_index box 5));
  let card = { box; hovered = false } in
  let title =
    make_text context ~id:("notification-card-" ^ action.key ^ "-title")
      (content [ styled ~attributes:A.bold ~fg:action.accent action.title ])
  in
  set_renderable (Text.as_renderable title) (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable (Text.as_renderable title) (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  add_child (Box.children box) (Text.as_renderable title);
  let subtitle =
    make_text context ~id:("notification-card-" ^ action.key ^ "-subtitle")
      (content [ styled ~fg:Palette.muted action.subtitle ])
  in
  set_renderable (Text.as_renderable subtitle) (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable (Text.as_renderable subtitle) (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  add_child (Box.children box) (Text.as_renderable subtitle);
  let spacer =
    make_text context ~id:("notification-card-" ^ action.key ^ "-spacer")
      (content [ styled "" ])
  in
  set_renderable (Text.as_renderable spacer) (fun value ->
      O.Renderable.set_flex_grow value (Some 1.0));
  set_renderable (Text.as_renderable spacer) (fun value ->
      O.Renderable.set_flex_shrink value (Some 1.0));
  add_child (Box.children box) (Text.as_renderable spacer);
  let cta =
    make_text context ~id:("notification-card-" ^ action.key ^ "-cta")
      (content
         [
           styled ~fg:action.accent "Click";
           styled ~fg:Palette.muted " or press ";
           styled ~attributes:A.bold ~fg:Palette.text action.key;
         ])
  in
  set_renderable (Text.as_renderable cta) (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable (Text.as_renderable cta) (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  add_child (Box.children box) (Text.as_renderable cta);
  ignore
    (expect_ok
       (O.Renderable.set_on_mouse_over renderable
          (Some (fun _event ->
               card.hovered <- true;
               update_card_colors card ~background:Palette.hover
                 ~border:action.accent))));
  ignore
    (expect_ok
       (O.Renderable.set_on_mouse_out renderable
          (Some (fun _event ->
               card.hovered <- false;
               update_card_colors card ~background:Palette.panel_alt
                 ~border:Palette.border))));
  ignore
    (expect_ok
       (O.Renderable.set_on_mouse_down renderable
          (Some (fun event ->
               if Int.equal (O.Renderable.mouse_button event) 0 then begin
                 update_card_background card Palette.pressed;
                 trigger_action demo action;
                 O.Renderable.mouse_stop_propagation event
               end))));
  ignore
    (expect_ok
       (O.Renderable.set_on_mouse_up renderable
          (Some (fun event ->
               if Int.equal (O.Renderable.mouse_button event) 0 then begin
                 update_card_background card
                   (if card.hovered then Palette.hover else Palette.panel_alt);
                 O.Renderable.mouse_stop_propagation event
               end))));
  card

let action_for_key = function
  | Key.Character bytes -> (
      match Bytes.to_string bytes with
      | "1" -> Some actions.(0)
      | "2" -> Some actions.(1)
      | "3" -> Some actions.(2)
      | "4" -> Some actions.(3)
      | _ -> None)
  | Key.Named _ -> None

let handle_key demo key_event =
  match Handler.key_event_kind key_event with
  | Handler.Keypress ->
      let modifiers = Handler.key_modifiers key_event in
      if not modifiers.ctrl && not modifiers.meta then begin
        match Handler.key key_event with
        | Key.Named Key.Escape -> demo.exit ()
        | key -> Option.iter (trigger_action demo) (action_for_key key)
      end
  | Handler.Keyrelease | Handler.Paste -> ()

let build_layout renderer ~exit =
  ignore (expect_ok (O.Renderer.set_background_color renderer ~color:Palette.bg));
  let context = O.Renderer.context renderer in
  let root =
    expect_ok
      (Box.create context ~id:"notification-demo-root"
         ~background_color:Palette.bg ())
  in
  let root_renderable = Box.as_renderable root in
  set_renderable root_renderable (fun value -> O.Renderable.set_flex_grow value (Some 1.0));
  set_renderable root_renderable (fun value ->
      O.Renderable.set_max_width value (O.Yoga.Percent 100.0));
  set_renderable root_renderable (fun value ->
      O.Renderable.set_max_height value (O.Yoga.Percent 100.0));
  set_renderable root_renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_column);
  set_renderable root_renderable (fun value ->
      O.Renderable.set_padding value ~edge:O.Yoga.All (O.Yoga.Point 1.0));
  add_child (O.Renderer.children renderer) root_renderable;
  let header =
    expect_ok
      (Box.create context ~id:"notification-demo-header"
         ~background_color:(color "#0d1b30")
         ~border_style:O.Lib.Border.Rounded ~border:Box.all_borders
         ~border_color:Palette.border_hot ~title:" OSC Notifications "
         ~title_alignment:O.Lib.Border.Center ())
  in
  let header_renderable = Box.as_renderable header in
  set_dimensions header_renderable ~width:(O.Yoga.Percent 100.0)
    ~height:(O.Yoga.Point 6.0);
  set_renderable header_renderable (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable header_renderable (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  set_renderable header_renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_column);
  set_renderable header_renderable (fun value ->
      O.Renderable.set_padding value ~edge:O.Yoga.All (O.Yoga.Point 1.0));
  set_renderable header_renderable (fun value ->
      O.Renderable.set_margin value ~edge:O.Yoga.Bottom (O.Yoga.Point 1.0));
  add_child (Box.children root) (Box.as_renderable header);
  let title =
    make_text context ~id:"notification-demo-title"
      (content
         [
           styled ~attributes:A.bold ~fg:Palette.cyan "System notifications";
           styled ~attributes:A.bold ~fg:Palette.muted
             " from terminal OSC sequences";
         ])
  in
  set_renderable (Text.as_renderable title) (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable (Text.as_renderable title) (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  add_child (Box.children header) (Text.as_renderable title);
  let status = make_text context ~id:"notification-demo-status" (content []) in
  set_renderable (Text.as_renderable status) (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable (Text.as_renderable status) (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  add_child (Box.children header) (Text.as_renderable status);
  let body =
    expect_ok
      (Box.create context ~id:"notification-demo-body"
         ~background_color:Palette.bg ())
  in
  let body_renderable = Box.as_renderable body in
  set_dimensions body_renderable ~width:(O.Yoga.Percent 100.0)
    ~height:O.Yoga.Auto;
  set_renderable body_renderable (fun value -> O.Renderable.set_flex_grow value (Some 1.0));
  set_renderable body_renderable (fun value -> O.Renderable.set_flex_shrink value (Some 1.0));
  set_renderable body_renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_column);
  add_child (Box.children root) (Box.as_renderable body);
  let cards_row =
    expect_ok
      (Box.create context ~id:"notification-demo-cards"
         ~background_color:Palette.bg ())
  in
  let cards_renderable = Box.as_renderable cards_row in
  set_dimensions cards_renderable ~width:(O.Yoga.Percent 100.0)
    ~height:O.Yoga.Auto;
  set_renderable cards_renderable (fun value -> O.Renderable.set_flex_grow value (Some 1.0));
  set_renderable cards_renderable (fun value -> O.Renderable.set_flex_shrink value (Some 1.0));
  set_renderable cards_renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_row);
  set_renderable cards_renderable (fun value ->
      O.Renderable.set_gap value ~gutter:O.Yoga.Gutter_all (O.Yoga.Point 1.0));
  set_renderable cards_renderable (fun value ->
      O.Renderable.set_margin value ~edge:O.Yoga.Bottom (O.Yoga.Point 1.0));
  add_child (Box.children body) (Box.as_renderable cards_row);
  let footer =
    expect_ok
      (Box.create context ~id:"notification-demo-footer"
         ~background_color:Palette.bg ())
  in
  let footer_renderable = Box.as_renderable footer in
  set_dimensions footer_renderable ~width:(O.Yoga.Percent 100.0)
    ~height:(O.Yoga.Point 16.0);
  set_renderable footer_renderable (fun value -> O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable footer_renderable (fun value -> O.Renderable.set_flex_shrink value (Some 0.0));
  set_renderable footer_renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_row);
  set_renderable footer_renderable (fun value ->
      O.Renderable.set_gap value ~gutter:O.Yoga.Gutter_all (O.Yoga.Point 1.0));
  add_child (Box.children body) (Box.as_renderable footer);
  let controls =
    expect_ok
      (Box.create context ~id:"notification-demo-controls"
         ~background_color:Palette.panel ~border_style:O.Lib.Border.Rounded
         ~border:Box.all_borders ~border_color:Palette.border
         ~title:" Controls " ~title_alignment:O.Lib.Border.Left ())
  in
  let controls_renderable = Box.as_renderable controls in
  set_dimensions controls_renderable ~width:(O.Yoga.Point 38.0)
    ~height:(O.Yoga.Percent 100.0);
  set_renderable controls_renderable (fun value ->
      O.Renderable.set_flex_grow value (Some 0.0));
  set_renderable controls_renderable (fun value ->
      O.Renderable.set_flex_shrink value (Some 0.0));
  set_renderable controls_renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_column);
  set_renderable controls_renderable (fun value ->
      O.Renderable.set_padding value ~edge:O.Yoga.All (O.Yoga.Point 1.0));
  let controls_text =
    make_text context ~id:"notification-demo-controls-text"
      (content
         [
           styled ~fg:Palette.cyan "1";
           styled " Quick ping\n";
           styled ~fg:Palette.lime "2";
           styled " Build complete\n";
           styled ~fg:Palette.violet "3";
           styled " Async task\n";
           styled ~fg:Palette.rose "4";
           styled " Needs attention\n";
           styled ~fg:Palette.muted "Mouse";
           styled " Click any card\n";
           styled ~fg:Palette.muted "Esc";
           styled " Exit demo";
         ])
  in
  add_child (Box.children controls) (Text.as_renderable controls_text);
  add_child (Box.children footer) (Box.as_renderable controls);
  let log =
    expect_ok
      (Box.create context ~id:"notification-demo-log"
         ~background_color:Palette.panel ~border_style:O.Lib.Border.Rounded
         ~border:Box.all_borders ~border_color:Palette.border
         ~title:" Activity " ~title_alignment:O.Lib.Border.Left ())
  in
  let log_renderable = Box.as_renderable log in
  set_dimensions log_renderable ~width:O.Yoga.Auto ~height:(O.Yoga.Percent 100.0);
  set_renderable log_renderable (fun value -> O.Renderable.set_flex_grow value (Some 1.0));
  set_renderable log_renderable (fun value -> O.Renderable.set_flex_shrink value (Some 1.0));
  set_renderable log_renderable (fun value ->
      O.Renderable.set_flex_direction value O.Yoga.Flex_column);
  set_renderable log_renderable (fun value ->
      O.Renderable.set_padding value ~edge:O.Yoga.All (O.Yoga.Point 1.0));
  let log_list =
    expect_ok
      (Scroll_box.create context ~id:"notification-demo-log-list" ~scroll_y:true
         ~scroll_x:false ())
  in
  Scroll_box.set_sticky_scroll log_list true;
  Scroll_box.set_sticky_start log_list (Some Scroll_box.Bottom);
  let vertical_scrollbar = Scroll_box.vertical_scrollbar log_list in
  ignore
    (expect_ok
       (Scroll_bar.set_track_foreground_color vertical_scrollbar Palette.cyan));
  ignore
    (expect_ok
       (Scroll_bar.set_track_background_color vertical_scrollbar Palette.border));
  let log_list_renderable = Scroll_box.as_renderable log_list in
  set_dimensions log_list_renderable ~width:O.Yoga.Auto
    ~height:(O.Yoga.Percent 100.0);
  set_renderable log_list_renderable (fun value -> O.Renderable.set_flex_grow value (Some 1.0));
  set_renderable log_list_renderable (fun value -> O.Renderable.set_flex_shrink value (Some 1.0));
  add_child (Box.children log) log_list_renderable;
  add_child (Box.children footer) (Box.as_renderable log);
  let clock =
    match expect_ok (O.Render_context.clock context) with
    | Some value -> value
    | None -> invalid_arg "notification demo requires an owner-local clock"
  in
  let live_lease = expect_ok (O.Renderer.acquire_live_lease renderer) in
  let demo =
    {
      renderer;
      root;
      status;
      log_list;
      clock;
      exit;
      cards = [||];
      log_rows = [];
      log_entry_id = 0;
      pending_timer = None;
      pending_generation = 0;
      live_lease = Some live_lease;
      key_subscription = None;
      capability_subscription = None;
      destroyed = false;
    }
  in
  let cards = Array.map (create_card demo context) actions in
  demo.cards <- cards;
  Array.iter (fun card -> add_child (Box.children cards_row) (Box.as_renderable card.box)) cards;
  update_status demo (current_capabilities demo);
  add_log demo "Demo ready. Press 1-4 or click a card." Palette.cyan;
  demo

let destroy demo =
  if not demo.destroyed then begin
    demo.destroyed <- true;
    cancel_pending_timer demo;
    Option.iter O.Event_subscription.cancel demo.key_subscription;
    Option.iter O.Event_subscription.cancel demo.capability_subscription;
    Option.iter O.Renderer.release_live_lease demo.live_lease;
    ignore
      (O.Layout_children.remove (O.Renderer.children demo.renderer)
         (Box.as_renderable demo.root));
    Box.destroy_recursively demo.root;
    demo.key_subscription <- None;
    demo.capability_subscription <- None;
    demo.live_lease <- None;
    demo.cards <- [||];
    demo.log_rows <- [];
    demo.log_entry_id <- 0
  end

let run renderer ~exit ~copy_to_clipboard =
  ignore copy_to_clipboard;
  let demo = build_layout renderer ~exit in
  let key_subscription =
    expect_ok (O.Renderer.on_keypress renderer (handle_key demo))
  in
  demo.key_subscription <- Some key_subscription;
  let capability_subscription =
    expect_ok
      (O.Renderer.on_capabilities renderer (fun capabilities ->
           update_status demo (Some capabilities)))
  in
  demo.capability_subscription <- Some capability_subscription;
  ignore (expect_ok (O.Renderer.attach_before_destroy renderer (fun () -> destroy demo)));
  Opentui_examples_lib.Standalone_keys.setup_common_demo_keys renderer ~on_ctrl_c:exit

let () =
  Eio_main.run @@ fun env ->
  Opentui_examples_lib.App.run ~detect_terminal_capabilities:true env
    ~init:(fun ~exit ~copy_to_clipboard renderer ->
      run renderer ~exit ~copy_to_clipboard)
