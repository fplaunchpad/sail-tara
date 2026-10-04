let json ~kind = function
  | `Assoc fields -> `Assoc (("kind", `String kind) :: fields)
  | json -> json
;;
