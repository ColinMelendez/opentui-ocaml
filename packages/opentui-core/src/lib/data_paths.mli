type paths = {
  global_config_path : string;
  global_config_file : string;
  local_config_file : string;
  global_data_path : string;
}

type t

val create :
  ?app_name:string ->
  home:string ->
  cwd:string ->
  getenv:(string -> string option) ->
  unit ->
  (t, Validate_dir_name.error) result

val app_name : t -> string
val set_app_name : t -> string -> (unit, Validate_dir_name.error) result
val paths : t -> paths
val on_paths_changed : t -> (paths -> unit) -> Event_subscription.t
