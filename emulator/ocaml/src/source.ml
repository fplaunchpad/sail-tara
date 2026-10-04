open! Import

let read filename =
  match In_channel.read_all filename with
  | contents -> Ok contents
  | exception Sys_error message -> Or_error.error_string message
;;

let fields text =
  String.split_lines text
  |> List.filter_mapi ~f:(fun index line ->
    let code = String.lsplit2 line ~on:';' |> Option.value_map ~default:line ~f:fst in
    match
      String.split_on_chars code ~on:[ ' '; '\t'; '\r'; '\011'; '\012' ]
      |> List.filter ~f:(Fn.non String.is_empty)
    with
    | [] -> None
    | fields -> Some (index + 1, fields))
;;
