open! Core

(* A line stays held this long after its key was last pressed. *)
let hold = Time_ns.Span.of_int_ms 150

(* An escape waits this long for the rest of its sequence before it counts as the Escape key. *)
let escape_wait = Time_ns.Span.of_int_ms 20

module Event = struct
  type t =
    | Press of Keys.Line.t
    | Leave
end

let line_of_letter : char -> Keys.Line.t option = function
  | 'w' | 'W' -> Some Up
  | 's' | 'S' -> Some Down
  | 'a' | 'A' -> Some Left
  | 'd' | 'D' -> Some Right
  | 'q' | 'Q' -> Some Quit
  | _ -> None
;;

(* An arrow key ends its escape sequence with a letter, in normal and application cursor mode. *)
let line_of_arrow : char -> Keys.Line.t option = function
  | 'A' -> Some Up
  | 'B' -> Some Down
  | 'C' -> Some Right
  | 'D' -> Some Left
  | _ -> None
;;

let press events line =
  match line with
  | Some line -> Event.Press line :: events
  | None -> events
;;

(* The events that [chars] make, and the escape sequence at their end that has not finished. *)
let rec decode events (chars : char list) =
  match chars with
  | [] -> List.rev events, []
  | '\003' :: _ -> List.rev (Event.Leave :: events), []
  | '\027' :: rest -> decode_escape events chars rest
  | letter :: rest -> decode (press events (line_of_letter letter)) rest

(* [chars] begins with an escape, which [rest] follows. *)
and decode_escape events chars rest =
  let unfinished = List.rev events, chars in
  match rest with
  | [] | [ 'O' ] -> unfinished
  | 'O' :: arrow :: rest -> decode (press events (line_of_arrow arrow)) rest
  | '[' :: parameters ->
    let _, tail = List.split_while parameters ~f:(Char.between ~low:' ' ~high:'?') in
    (match tail with
     | [] -> unfinished
     | final :: rest when Char.between final ~low:'@' ~high:'~' ->
       decode (press events (line_of_arrow final)) rest
     | broken -> decode events broken)
  | _ -> List.rev (Event.Leave :: events), []
;;

type t =
  { mutable pending : string (* An escape sequence that has not finished. *)
  ; mutable pending_since : Time_ns.t
  ; release : Time_ns.t array (* When each line is let go, by its index. *)
  ; mutable leaving : bool
  }

let create () =
  { pending = ""
  ; pending_since = Time_ns.epoch
  ; release = Array.create ~len:(List.length Keys.Line.all) Time_ns.epoch
  ; leaving = false
  }
;;

let feed t ~now bytes =
  let events, pending = [%string "%{t.pending}%{bytes}"] |> String.to_list |> decode [] in
  t.pending <- String.of_char_list pending;
  t.pending_since <- now;
  List.iter events ~f:(function
    | Press line -> t.release.(Keys.Line.index line) <- Time_ns.add now hold
    | Leave -> t.leaving <- true)
;;

let deadline t =
  if String.is_empty t.pending then None else Some (Time_ns.add t.pending_since escape_wait)
;;

let expire t ~now =
  match deadline t with
  | Some deadline when Time_ns.O.(now >= deadline) ->
    t.pending <- "";
    t.leaving <- true
  | Some _ | None -> ()
;;

let leaving t = t.leaving

let held t ~now =
  List.filter Keys.Line.all ~f:(fun line -> Time_ns.O.(now < t.release.(Keys.Line.index line)))
  |> Keys.of_lines
;;
