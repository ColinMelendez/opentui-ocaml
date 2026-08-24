let create ?(color = Color.create ()) ?(intensity = 1.0) () =
  let target = Object3d.make ~name:"directional-light-target" () in
  let node =
    Object3d.make
      ~kind:(Object3d.Directional_light ({ color; intensity }, target))
      ()
  in
  (* three.js DirectionalLight shines from above by default. *)
  Vector3.set (Object3d.position node) 0.0 1.0 0.0;
  node

let color node =
  match Object3d.kind node with
  | Object3d.Directional_light (state, _) -> state.color
  | _ -> raise (Invalid_argument "Directional_light.color: not a light")

let intensity node =
  match Object3d.kind node with
  | Object3d.Directional_light (state, _) -> state.intensity
  | _ -> raise (Invalid_argument "Directional_light.intensity: not a light")

let set_intensity node intensity =
  match Object3d.kind node with
  | Object3d.Directional_light (state, _) -> state.intensity <- intensity
  | _ -> raise (Invalid_argument "Directional_light.set_intensity: not a light")

let target node =
  match Object3d.kind node with
  | Object3d.Directional_light (_, target) -> target
  | _ -> raise (Invalid_argument "Directional_light.target: not a light")

let set_target node target =
  match Object3d.kind node with
  | Object3d.Directional_light (_, current) ->
      if not (current == target) then
        node.kind <-
          (match Object3d.kind node with
          | Object3d.Directional_light (state, _) ->
              Object3d.Directional_light (state, target)
          | other -> other)
  | _ -> raise (Invalid_argument "Directional_light.set_target: not a light")
