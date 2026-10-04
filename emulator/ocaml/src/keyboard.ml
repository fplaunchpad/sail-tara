open! Import

(* A line stays held this long after its key was last pressed. *)
let hold = Time_ns.Span.of_int_ms 150

(* An escape waits this long for the rest of its sequence before it counts as the Escape key. *)
let escape_wait = Time_ns.Span.of_int_ms 20

module Request = struct
  type t =
    | Stay
    | Leave
end

module Event = struct
  type t =
    | Press of Keys.Line.t
    | Leave_key
end

(* [events], reversed, and the press of [line] if it is one. *)
let press events line =
  match line with
  | Some line -> Event.Press line :: events
  | None -> events
;;

(* [events], reversed into their order, and nothing left over. *)
let finished events = List.rev events, []

(* The events that [chars] make, and the escape sequence at their end that has not finished.
   [events] are those before [chars], reversed. *)
let rec decode events (chars : char list) =
  match chars with
  | [] -> finished events
  | '\003' :: _ -> finished (Event.Leave_key :: events)
  | '\027' :: rest -> decode_escape events chars rest
  | key :: rest ->
    let events = Keys.Line.of_key key |> press events in
    decode events rest

(* [chars] begins with an escape, which [rest] follows. *)
and decode_escape events chars rest =
  let unfinished = List.rev events, chars in
  match rest with
  | [] | [ 'O' ] -> unfinished
  | 'O' :: arrow :: rest ->
    let events = Keys.Line.of_arrow arrow |> press events in
    decode events rest
  | '[' :: parameters ->
    let _, tail = List.split_while parameters ~f:(Char.between ~low:' ' ~high:'?') in
    (match tail with
     | [] -> unfinished
     | final :: rest when Char.between final ~low:'@' ~high:'~' ->
       let events = Keys.Line.of_arrow final |> press events in
       decode events rest
     | broken -> decode events broken)
  | _ -> finished (Event.Leave_key :: events)
;;

type t =
  { pending : string (* An escape sequence that has not finished. *)
  ; pending_since : Time_ns.t
  ; release : Time_ns.t Keys.Line.Map.t (* When each line held is let go. *)
  ; request : Request.t
  }

let create () =
  ({ pending = ""; pending_since = Time_ns.epoch; release = Keys.Line.Map.empty; request = Stay }
   : t)
;;

let feed t ~now bytes =
  let events, pending = [%string "%{t.pending}%{bytes}"] |> String.to_list |> decode [] in
  let pending = String.of_char_list pending in
  List.fold events ~init:{ t with pending; pending_since = now } ~f:(fun t event ->
    match event with
    | Press line ->
      let released_at = Time_ns.add now hold in
      { t with release = Map.set t.release ~key:line ~data:released_at }
    | Leave_key -> { t with request = Leave })
;;

let deadline t =
  match t.pending with
  | "" -> None
  | _ -> Time_ns.add t.pending_since escape_wait |> Some
;;

let expire t ~now =
  match deadline t with
  | Some deadline when Time_ns.O.(now >= deadline) -> { t with pending = ""; request = Leave }
  | Some _ | None -> t
;;

let request t = t.request

let held t ~now =
  Map.filter t.release ~f:(fun released_at -> Time_ns.O.(now < released_at))
  |> Map.keys
  |> Keys.of_lines
;;
