type error = Invalid_number of string | Invalid_percentage of string | Invalid_value of string
type spacing = Pixels of float | Percentage of float | Auto
type dimension = Pixels of float | Percentage of float | Auto | Undefined
type position = spacing
type overflow = Visible | Hidden | Scroll
type position_type = Relative | Absolute | Static

let finite_nonnegative value = Float.is_finite value && Float.compare value 0.0 >= 0

let nonnegative ~name value =
  if finite_nonnegative value then Ok () else Error (Invalid_number name)

let validate_options ~id ~width ~height =
  match width with
  | Some value ->
      (match nonnegative ~name:(id ^ ".width") value with
      | Error error -> Error error
      | Ok () ->
          (match height with
          | Some value -> nonnegative ~name:(id ^ ".height") value
          | None -> Ok ()))
  | None ->
      (match height with
      | Some value -> nonnegative ~name:(id ^ ".height") value
      | None -> Ok ())

let parse_float value =
  match float_of_string_opt value with
  | Some number when Float.is_finite number -> Some number
  | Some _ | None -> None

let is_valid_percentage value =
  String.length value > 1
  && Char.equal (String.get value (String.length value - 1)) '%'
  &&
  match parse_float (String.sub value 0 (String.length value - 1)) with
  | Some number -> Float.is_finite number
  | None -> false

let percentage value =
  if not (is_valid_percentage value) then Error (Invalid_percentage value)
  else
    match parse_float (String.sub value 0 (String.length value - 1)) with
    | Some number -> Ok number
    | None -> Error (Invalid_percentage value)

let percentage_spacing number : spacing = Percentage number

let number_or_percentage value : (spacing, error) result =
  if is_valid_percentage value then Result.map percentage_spacing (percentage value)
  else
    match value with
    | "auto" -> Ok Auto
    | _ ->
        (match parse_float value with
        | Some number when finite_nonnegative number -> Ok (Pixels number)
        | Some _ | None -> Error (Invalid_value value))

let margin value : (spacing, error) result = number_or_percentage value

let padding value : (spacing, error) result =
  match number_or_percentage value with
  | Ok Auto -> Error (Invalid_value "padding:auto")
  | Ok (Pixels value) -> Ok (Pixels value : spacing)
  | Ok (Percentage value) -> Ok (Percentage value : spacing)
  | Error error -> Error error

let position value : (position, error) result =
  match number_or_percentage value with
  | Ok (Pixels number) -> Ok (Pixels number)
  | Ok (Percentage number) -> Ok (Percentage number)
  | Ok Auto -> Ok Auto
  | Error error -> Error error

let dimension value : (dimension, error) result =
  match value with
  | "undefined" -> Ok Undefined
  | "auto" -> Ok Auto
  | _ ->
      (match number_or_percentage value with
      | Ok (Pixels number) -> Ok (Pixels number : dimension)
      | Ok (Percentage number) -> Ok (Percentage number : dimension)
      | Ok Auto -> Ok (Auto : dimension)
      | Error error -> Error error)

let flex_basis value =
  match value with
  | "undefined" -> Ok None
  | _ -> Result.map (fun spacing -> Some spacing) (number_or_percentage value)

let size value =
  match value with
  | "undefined" -> Ok None
  | _ -> Result.map (fun dimension -> Some dimension) (dimension value)

let overflow = function
  | "visible" -> Ok Visible
  | "hidden" -> Ok Hidden
  | "scroll" -> Ok Scroll
  | value -> Error (Invalid_value value)

let position_type = function
  | "relative" -> Ok Relative
  | "absolute" -> Ok Absolute
  | "static" -> Ok Static
  | value -> Error (Invalid_value value)

let message = function
  | Invalid_number name -> "invalid non-negative number for " ^ name
  | Invalid_percentage value -> "invalid percentage: " ^ value
  | Invalid_value value -> "invalid renderable value: " ^ value
