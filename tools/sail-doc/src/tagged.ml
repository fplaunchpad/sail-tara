let json ~kind = function
  | `Assoc fields -> `Assoc (("kind", `String kind) :: fields)
  | json -> json
;;

let rec tree = function
  | `List [ `String kind; `Assoc fields ] ->
    `Assoc
      (("kind", `String (String.lowercase_ascii kind))
       :: List.map (fun (key, value) -> key, tree value) fields)
  | `List values -> `List (List.map tree values)
  | `Assoc fields -> `Assoc (List.map (fun (key, value) -> key, tree value) fields)
  | value -> value
;;
