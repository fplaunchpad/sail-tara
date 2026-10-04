open! Core

type t =
  { initial : Keys.t
  ; entries : (int * Keys.t) array
  }

let constant initial = { initial; entries = [||] }

(* A line of the script, with its number: STEP and KEYS. *)
let parse_line (line, fields) =
  let parsed =
    match fields with
    | [ step; keys ] ->
      let%map.Or_error step = Number.decimal step
      and keys = Keys.of_string keys in
      line, step, keys
    | _ -> Or_error.error_s [%message "expected STEP KEYS" (fields : string list)]
  in
  Or_error.tag_s parsed ~tag:[%message (line : int)]
;;

(* Every step must come after the one before it. *)
let check_increasing lines =
  List.fold_result lines ~init:(-1) ~f:(fun previous (line, step, _) ->
    if step > previous
    then Ok step
    else Or_error.error_s [%message "step does not follow the one before" (line : int) (step : int)])
  |> Or_error.ignore_m
;;

let parse text =
  let%bind.Or_error lines = Source.fields text |> List.map ~f:parse_line |> Or_error.all in
  let%map.Or_error () = check_increasing lines in
  List.map lines ~f:(fun (_, step, keys) -> step, keys) |> Array.of_list
;;

let load filename ~initial =
  let%bind.Or_error text = Source.read filename in
  let%map.Or_error entries = parse text |> Or_error.tag ~tag:filename in
  { initial; entries }
;;

let at { initial; entries } ~retired =
  match
    Array.binary_search
      entries
      `Last_less_than_or_equal_to
      retired
      ~compare:(fun (step, _) retired -> Int.compare step retired)
  with
  | Some index -> snd entries.(index)
  | None -> initial
;;
