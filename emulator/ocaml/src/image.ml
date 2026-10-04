open! Import

let memory_bytes = 2048

module Encoding = struct
  type t =
    | Bin
    | Hex
  [@@deriving enumerate, string ~capitalize:"snake_case"]

  let of_filename filename =
    List.find all ~f:(fun encoding ->
      let extension = to_string encoding in
      String.is_suffix filename ~suffix:[%string ".%{extension}"])
  ;;
end

let word ~line token =
  if String.length token <= 4 && String.for_all token ~f:Char.is_hex_digit
  then [%string "0x%{token}"] |> Int.of_string |> Ok
  else Or_error.error_s [%message "malformed word" (line : int) token]
;;

let words text =
  Source.fields text
  |> List.concat_map ~f:(fun (line, tokens) -> List.map tokens ~f:(word ~line))
  |> Or_error.all
;;

let bytes (encoding : Encoding.t) contents =
  match encoding with
  | Bin -> String.to_list contents |> List.map ~f:Char.to_int |> Ok
  | Hex ->
    let%map.Or_error words = words contents in
    List.concat_map words ~f:(fun word -> [ word lsr 8; word land 0xFF ])
;;

let load filename =
  let%bind.Or_error encoding =
    Encoding.of_filename filename
    |> Result.of_option ~error:(Error.of_string "expected a .bin or .hex image")
    |> Or_error.tag ~tag:filename
  in
  let%bind.Or_error contents = Source.read filename in
  let%bind.Or_error bytes = bytes encoding contents |> Or_error.tag ~tag:filename in
  if List.length bytes > memory_bytes
  then Or_error.error_s [%message [%string "larger than %{memory_bytes#Int} bytes"] filename]
  else (
    List.iteri bytes ~f:(fun address -> Machine.poke ~address);
    Ok ())
;;
