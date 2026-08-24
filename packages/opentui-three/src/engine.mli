type t
(** One headless three renderer: a WebGPU device, an offscreen color target,
    staging readback, the unlit and lambert pipelines, and per-mesh GPU
    state cached by node identity. *)

val create : width:int -> height:int -> unit -> (t, Opentui_wgpu.Wgpu.Error.t) result
(** Opens the device and builds the render surface. Failing intermediate
    steps release every partially created resource. *)

val submit :
  t ->
  root:Object3d.t ->
  camera:Object3d.t ->
  clear_color:float * float * float * float ->
  unit ->
    (unit, Opentui_wgpu.Wgpu.Error.t) result
(** The first half of {!render}: update world matrices from [root], refresh
    the camera's view, collect visible meshes sorted front-to-back, upload
    per-mesh uniforms, and encode every draw into one submitted frame.

    Lighting gathers every visible ambient light and the first visible
    directional light - the phase-1 uniform block carries one directional
    slot; further lights land with the phase-2 shader work. The camera must
    be a perspective-camera node. Rendering assumes convex geometry without
    mutual screen overlap: there is no depth buffer, only back-face
    culling (documented phase-1 limitation). *)

val stage : t -> (unit, Opentui_wgpu.Wgpu.Error.t) result
(** The second half of {!render}: block until the submitted frame's pixels
    land in the owned staging buffer for {!snapshot}. One readback path,
    awaited immediately - reference parity. *)

val render :
  t ->
  root:Object3d.t ->
  camera:Object3d.t ->
  clear_color:float * float * float * float ->
  unit ->
    (unit, Opentui_wgpu.Wgpu.Error.t) result
(** [submit] followed by [stage]: one complete frame ending with staged
    pixels ready for {!snapshot}. *)

val snapshot : t -> string
(** [width * height * 4] RGBA bytes of the last staged frame with row
    padding stripped. Only meaningful in [`None] and [`Cpu] modes. *)

type super_sample = [ `None | `Cpu | `Gpu ]

type sample_algorithm = [ `Standard | `Pre_squeezed ]

val set_super_sample_algorithm :
  t -> sample_algorithm -> (unit, Opentui_wgpu.Wgpu.Error.t) result
(** Selects the reference's supersampling variant for the [`Gpu] path;
    rebuilding the compute state is automatic. *)

val set_super_sample : t -> super_sample -> (unit, Opentui_wgpu.Wgpu.Error.t) result
(** Selects the staging path. [`Gpu] builds the supersampling compute state
    against the current target; rebuilding after resize is automatic. *)

val upload_frame :
  t -> data:string -> bytes_per_row:int -> (unit, Opentui_wgpu.Wgpu.Error.t) result
(** Queue-writes tightly packed rgba8unorm rows into the current frame
    texture. Rows are NOT padded by this call; pass [bytes_per_row] matching
    [data]'s layout. *)

val last_cell_grid : t -> int * int
(** The active supersampler's compute grid in cells; (0, 0) before the
    first [`Gpu] stage. *)

val last_cells : t -> string
(** Raw 48-byte CellResult records staged by the most recent {!stage} call
    in [`Gpu] mode; empty otherwise. Decoding lives in
    {!Cell_conversion.write_gpu_records}. *)

val resize : t -> width:int -> height:int -> (unit, Opentui_wgpu.Wgpu.Error.t) result
(** Rebuilds the offscreen target and readback for a new size. *)

val width : t -> int

val height : t -> int

val destroy : t -> unit
(** Releases all GPU state including the device. *)
