module Id = Plugin_id
module Failure = Plugin_failure
module Reporter = Plugin_reporter

type errors = Plugin_host.errors
type instance = Plugin_host.instance
type 'capabilities definition = 'capabilities Plugin_host.definition

let errors_to_list (first, rest) = first :: rest

let define ~id ~order ~install = Plugin_host.define ~id ~order ~install

module Scope = struct
  type t = Plugin_host.scope

  let contribute = Slot.contribute
  let on_release = Plugin_host.Scope.on_release
end

module Instance = struct
  type t = instance

  let id = Plugin_host.Instance.id
  let order = Plugin_host.Instance.order
  let set_order = Plugin_host.Instance.set_order
  let uninstall = Plugin_host.Instance.uninstall
end

module Host = struct
  type t = Plugin_host.t

  let create = Plugin_host.Host.create
  let install = Plugin_host.Host.install
  let close = Plugin_host.Host.close
end
