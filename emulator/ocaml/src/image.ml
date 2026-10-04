open! Core

let memory_bytes = 2048

module Format = struct
  type t =
    | Bin
    | Hex
  [@@deriving enumerate, string ~capitalize:"snake_case"]

  let of_filename filename =
    List.find all ~f:(fun format ->
      String.is_suffix filename ~suffix:[%string ".%{to_string format}"])
  ;;
end

let word ~line token =
  if String.length token <= 4 && String.for_all token ~f:Char.is_hex_digit
  then Ok (Int.of_string [%string "0x%{token}"])
  else Or_error.error_s [%message "malformed word" (line : int) token]
;;

let words text =
  Source.fields text
  |> List.concat_map ~f:(fun (line, tokens) -> List.map tokens ~f:(word ~line))
  |> Or_error.all
;;

let bytes (format : Format.t) contents =
  match format with
  | Bin -> Ok (String.to_list contents |> List.map ~f:Char.to_int)
  | Hex ->
    let%map.Or_error words = words contents in
    List.concat_map words ~f:(fun w -> [ w lsr 8; w land 0xFF ])
;;

let load filename =
  let%bind.Or_error format =
    Format.of_filename filename
    |> Result.of_option ~error:(Error.of_string "expected a .bin or .hex image")
    |> Or_error.tag ~tag:filename
  in
  let%bind.Or_error contents = Source.read filename in
  let%bind.Or_error bytes = bytes format contents |> Or_error.tag ~tag:filename in
  if List.length bytes > memory_bytes
  then Or_error.error_s [%message [%string "larger than %{memory_bytes#Int} bytes"] filename]
  else Ok (List.iteri bytes ~f:(fun address -> Machine.poke ~address))
;;
