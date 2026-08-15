type mode = Undefined | Exactly | At_most

type callback =
  width:float -> width_mode:mode -> height:float -> height_mode:mode -> float * float

type registration = { pointer : Nativeint.t; callback : callback }

let registrations : registration list ref = ref []
let installed = ref false

let mode_of_int32 value =
  match Int32.to_int value with
  | 0 -> Undefined
  | 1 -> Exactly
  | 2 -> At_most
  | _ -> Undefined

let dispatch (pointer, width, width_mode, height, height_mode) =
  match
    List.find_opt
      (fun registration -> Nativeint.equal registration.pointer pointer)
      !registrations
  with
  | None -> Float.nan, Float.nan
  | Some registration ->
      registration.callback ~width ~width_mode:(mode_of_int32 width_mode) ~height
        ~height_mode:(mode_of_int32 height_mode)

let ensure_installed () =
  if not !installed then begin
    Yoga.Node.Private.set_measure_callback dispatch;
    installed := true
  end

let remove_pointer pointer =
  registrations :=
    List.filter
      (fun registration -> not (Nativeint.equal registration.pointer pointer))
      !registrations

let attach node callback =
  Result.bind (Yoga.Node.Private.native_pointer node) (fun pointer ->
      ensure_installed ();
      remove_pointer pointer;
      registrations := { pointer; callback } :: !registrations;
      match Yoga.Node.Private.set_measure_func node true with
      | Ok () -> Ok ()
      | Error error ->
          remove_pointer pointer;
          if List.is_empty !registrations then begin
            Yoga.Node.Private.clear_measure_callback ();
            installed := false
          end;
          Error error)

let detach node =
  Result.bind (Yoga.Node.Private.native_pointer node) (fun pointer ->
      Result.bind (Yoga.Node.Private.unset_measure_func node) (fun () ->
          remove_pointer pointer;
          if List.is_empty !registrations then begin
            Yoga.Node.Private.clear_measure_callback ();
            installed := false
          end;
          Ok ()))
