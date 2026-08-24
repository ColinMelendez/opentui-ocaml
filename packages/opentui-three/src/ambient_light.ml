let create ?(color = Color.create ()) ?(intensity = 1.0) () =
  Object3d.make ~kind:(Object3d.Ambient_light { color; intensity }) ()

let color node =
  match Object3d.kind node with
  | Object3d.Ambient_light state -> state.color
  | _ -> raise (Invalid_argument "Ambient_light.color: not a light")

let intensity node =
  match Object3d.kind node with
  | Object3d.Ambient_light state -> state.intensity
  | _ -> raise (Invalid_argument "Ambient_light.intensity: not a light")

let set_intensity node intensity =
  match Object3d.kind node with
  | Object3d.Ambient_light state -> state.intensity <- intensity
  | _ -> raise (Invalid_argument "Ambient_light.set_intensity: not a light")
