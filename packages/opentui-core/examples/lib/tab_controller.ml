(* Port of vendor/opentui/packages/examples/src/lib/tab-controller.ts.

   A tabbed container: a TabSelect renderable bar plus one Box group per tab.
   The current tab group is visible and receives a per-frame update callback
   driven by a renderer pre-render driver. Switching tabs hides the old group,
   initializes and shows the new one, and runs its show/hide lifecycle. *)

module O = Opentui_core

type group = O.Renderables.Box.t

type tab_spec = {
  title : string;
  init : group:group -> (unit, O.Error.t) result;
  update : delta_ms:float -> group:group -> (unit, O.Error.t) result;
  show : group:group -> unit;
  hide : group:group -> unit;
}

type tab = {
  spec : tab_spec;
  group : group;
  initialized : bool ref;
}

type t = {
  renderer : O.Renderer.t;
  context : O.Render_context.t;
  container : group;
  bar : O.Renderables.Tab_select.t;
  bar_height : int;
  mutable tabs : tab list;
  mutable current_index : int;
}

let expect_ok result =
  match result with
  | Ok value -> value
  | Error error -> invalid_arg (O.Error.message error)

let expect_unit result =
  match result with
  | Ok () -> ()
  | Error error -> invalid_arg (O.Error.message error)

let bar controller = controller.bar
let container controller = controller.container
let as_renderable controller = O.Renderables.Box.as_renderable controller.container
let renderer controller = controller.renderer
let current_index controller = controller.current_index
let tab_count controller = List.length controller.tabs

let option_of_tab index count tab =
  {
    O.Renderables.Select.name = tab.spec.title;
    description = Printf.sprintf "Tab %d/%d" (index + 1) count;
    value = None;
  }

let refresh_bar controller =
  let count = List.length controller.tabs in
  let options = List.mapi (fun index tab -> option_of_tab index count tab) controller.tabs in
  expect_unit (O.Renderables.Tab_select.set_options controller.bar options)

let position_absolute renderable ~left ~top =
  ignore (expect_ok (O.Renderable.set_position_type renderable O.Yoga.Position_absolute));
  ignore (expect_ok (O.Renderable.set_position renderable ~edge:O.Yoga.Left (O.Yoga.Point left)));
  ignore (expect_ok (O.Renderable.set_position renderable ~edge:O.Yoga.Top (O.Yoga.Point top)))

let current_tab controller =
  match List.nth_opt controller.tabs controller.current_index with
  | Some tab -> tab
  | None -> invalid_arg "tab controller has no tabs"

let current_tab_title controller = (current_tab controller).spec.title
let current_group controller = (current_tab controller).group

let switch_to_tab controller index =
  if index < 0 || index >= List.length controller.tabs then ()
  else if Int.equal index controller.current_index then ()
  else begin
    let previous = current_tab controller in
    ignore (expect_ok (O.Renderable.set_visible (O.Renderables.Box.as_renderable previous.group) false));
    previous.spec.hide ~group:previous.group;
    controller.current_index <- index;
    expect_unit (O.Renderables.Tab_select.set_selected_index controller.bar index);
    let next = current_tab controller in
    ignore (expect_ok (O.Renderable.set_visible (O.Renderables.Box.as_renderable next.group) true));
    if not !(next.initialized) then begin
      ignore (expect_unit (next.spec.init ~group:next.group));
      next.initialized := true
    end;
    next.spec.show ~group:next.group
  end

let next_tab controller =
  let count = List.length controller.tabs in
  if count > 0 then switch_to_tab controller ((controller.current_index + 1) mod count)

let previous_tab controller =
  let count = List.length controller.tabs in
  if count > 0 then
    switch_to_tab controller ((controller.current_index - 1 + count) mod count)

let create ?(bar_height = 4) ?(show_description = true)
    ?(background_color = O.Color.transparent) ~text_color ~selected_background_color
    ~selected_text_color ~selected_description_color ~renderer ~id () =
  let context = O.Renderer.context renderer in
  let container =
    expect_ok (O.Renderables.Box.create context ~id ~background_color ())
  in
  position_absolute (O.Renderables.Box.as_renderable container) ~left:0.0 ~top:0.0;
  ignore
    (expect_ok
       (O.Renderable.set_width (O.Renderables.Box.as_renderable container)
          (O.Yoga.Percent 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_height (O.Renderables.Box.as_renderable container)
          (O.Yoga.Percent 100.0)));
  let bar =
    expect_ok
      (O.Renderables.Tab_select.create context ~id:(id ^ "-tabs")
         ~selected_background_color ~selected_text_color ~text_color
         ~selected_description_color ~background_color ~show_scroll_arrows:true
         ~show_description ~show_underline:true ())
  in
  position_absolute (O.Renderables.Tab_select.as_renderable bar) ~left:0.0 ~top:0.0;
  ignore
    (expect_ok
       (O.Renderable.set_width (O.Renderables.Tab_select.as_renderable bar)
          (O.Yoga.Percent 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_height (O.Renderables.Tab_select.as_renderable bar)
          (O.Yoga.Point (float_of_int bar_height))));
  ignore
    (expect_ok
       (O.Layout_children.add (O.Renderables.Box.children container)
          (O.Renderables.Tab_select.as_renderable bar)));
  let controller =
    { renderer; context; container; bar; bar_height; tabs = []; current_index = 0 }
  in
  (* The reference TabControllerRenderable switches tabs when the bar
     selection changes; arrow-key navigation reaches the focused TabSelect and
     its SELECTION_CHANGED event drives the visible group. *)
  ignore
    (O.Renderables.Tab_select.on_selection_changed controller.bar
       (fun change -> switch_to_tab controller change.index));
  controller

let add_tab controller spec =
  let index = List.length controller.tabs in
  let group =
    expect_ok
      (O.Renderables.Box.create controller.context
         ~id:(Printf.sprintf "tab-%d" index) ~background_color:O.Color.transparent ())
  in
  position_absolute (O.Renderables.Box.as_renderable group)
    ~left:0.0 ~top:(float_of_int controller.bar_height);
  ignore
    (expect_ok
       (O.Renderable.set_width (O.Renderables.Box.as_renderable group)
          (O.Yoga.Percent 100.0)));
  ignore
    (expect_ok
       (O.Renderable.set_height (O.Renderables.Box.as_renderable group)
          (O.Yoga.Percent 100.0)));
  ignore (expect_ok (O.Renderable.set_visible (O.Renderables.Box.as_renderable group) false));
  ignore
    (expect_ok
       (O.Layout_children.add (O.Renderables.Box.children controller.container)
          (O.Renderables.Box.as_renderable group)));
  let tab = { spec; group; initialized = ref false } in
  controller.tabs <- controller.tabs @ [ tab ];
  refresh_bar controller;
  if Int.equal (List.length controller.tabs) 1 then begin
    ignore (expect_ok (O.Renderable.set_visible (O.Renderables.Box.as_renderable group) true));
    ignore (expect_unit (spec.init ~group));
    tab.initialized := true;
    spec.show ~group
  end;
  tab

let get_renderable controller id =
  O.Renderable.find_descendant_by_id (O.Renderables.Box.as_renderable controller.container) id

let update controller delta_ms =
  match List.nth_opt controller.tabs controller.current_index with
  | Some tab -> expect_unit (tab.spec.update ~delta_ms ~group:tab.group)
  | None -> ()

let focus controller = O.Renderable.focus (O.Renderables.Tab_select.as_renderable controller.bar)
let blur controller = O.Renderable.blur (O.Renderables.Tab_select.as_renderable controller.bar)

let is_focused controller =
  O.Renderable.focused (O.Renderables.Tab_select.as_renderable controller.bar)

let set_selected_index controller index =
  O.Renderables.Tab_select.set_selected_index controller.bar index

let destroy controller =
  List.iter (fun tab -> O.Renderables.Box.destroy tab.group) controller.tabs;
  O.Renderables.Tab_select.destroy controller.bar;
  O.Renderables.Box.destroy controller.container