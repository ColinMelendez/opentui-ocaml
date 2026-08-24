type t
(** One headless three renderer: a WebGPU device, an offscreen color target,
    staging readback, the unlit and lambert pipelines, and per-mesh GPU
    state cached by node identity. *)

val create : width:int -> height:int -> unit -> (t, Opentui_wgpu.Wgpu.Error.t) result
(** Opens the device and builds the render surface. Failing intermediate
    steps release every partially created resource. *)

val render :
  t ->
  root:Object3d.t ->
  camera:Object3d.t ->
  clear_color:float * float * float * float ->
  unit ->
    (unit, Opentui_wgpu.Wgpu.Error.t) result
(** One frame: update world matrices from [root], refresh the camera's view,
    collect visible meshes sorted front-to-back, upload per-mesh uniforms,
    draw through the material-selected pipeline into the offscreen target,
    and stage the pixels for {!snapshot}.

    Lighting gathers every visible ambient light and the first visible
    directional light - the phase-1 uniform block carries one directional
    slot; further lights land with the phase-2 shader work. The camera must
    be a perspective-camera node. Rendering assumes convex geometry without
    mutual screen overlap: there is no depth buffer, only back-face
    culling (documented phase-1 limitation). *)

val snapshot : t -> string
(** [width * height * 4] RGBA bytes of the last staged frame with row
    padding stripped. *)

val resize : t -> width:int -> height:int -> (unit, Opentui_wgpu.Wgpu.Error.t) result
(** Rebuilds the offscreen target and readback for a new size. *)

val width : t -> int

val height : t -> int

val destroy : t -> unit
(** Releases all GPU state including the device. *)
