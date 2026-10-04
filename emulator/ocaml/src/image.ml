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

let word token =
  if String.length token <= 4 && String.for_all token ~f:Char.is_hex_digit
  then Ok (Int.of_string [%string "0x%{token}"])
  else Or_error.error_s [%message "malformed word" token]
;;

let words text =
  String.split_lines text
  |> List.concat_map ~f:(fun line ->
    let code = String.lsplit2 line ~on:';' |> Option.value_map ~default:line ~f:fst in
    String.split_on_chars code ~on:[ ' '; '\t'; '\r' ] |> List.filter ~f:(Fn.non String.is_empty))
  |> List.map ~f:word
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
  in
  let%bind.Or_error contents = Or_error.try_with (fun () -> In_channel.read_all filename) in
  let%bind.Or_error bytes = bytes format contents in
  if List.length bytes > memory_bytes
  then Or_error.error_string [%string "larger than %{memory_bytes#Int} bytes"]
  else Ok (List.iteri bytes ~f:(fun address -> Machine.poke ~address))
;;
