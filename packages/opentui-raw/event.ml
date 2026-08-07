type t = {
  name : bytes;
  data : bytes;
}

let name event = event.name
let data event = event.data

module Private = struct
  let of_native name data = { name; data }
end
