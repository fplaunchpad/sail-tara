open! Core

module Options = struct
  type t =
    { image : Filename.t
    ; max_steps : int
    ; hz : int
    }
end

let frames_per_second = 30
let frame_time = Time_ns.Span.of_sec (1. /. Float.of_int frames_per_second)

(* How many instructions to run before each frame. *)
module Budget = struct
  type t =
    { hz : int
    ; mutable carry : int
    }

  let create ~hz = { hz; carry = 0 }

  (* [hz] a second makes [hz / frames_per_second] a frame, and the remainder is carried to the next
     frames so that the rate is exact. As many as fit if [hz] is 0. *)
  let next t =
    if t.hz = 0
    then Int.max_value
    else (
      t.carry <- t.carry + (t.hz % frames_per_second);
      let extra = t.carry / frames_per_second in
      t.carry <- t.carry % frames_per_second;
      (t.hz / frames_per_second) + extra)
  ;;
end

type t =
  { run : Run.t
  ; keyboard : Keyboard.t
  ; display : Display.t
  ; budget : Budget.t
  ; mutable closed : bool (* The terminal has gone away. *)
  ; mutable draw_time : Time_ns.Span.t (* What the last draw took. *)
  }

let leaving t = t.closed || Keyboard.leaving t.keyboard || Terminal.interrupted ()

let status_line run ~keys =
  let state = Option.value_map (Run.status run) ~default:"running" ~f:Run.Status.to_string in
  let pc = Machine.pc () |> sprintf "%04x" in
  let steps = Run.retired run in
  let held =
    List.map Keys.Line.all ~f:(fun line ->
      if Keys.mem keys line then Keys.Line.letter line else '-')
    |> String.of_char_list
  in
  [%string "%{state}  pc 0x%{pc}  steps %{steps#Int}  keys %{held}"]
;;

(* Run the instructions of one frame: as many as the budget allows, but none that start after
   [until], except the first. Returns how many ran. *)
let advance t ~keys ~until =
  let budget = Budget.next t.budget in
  let rec go executed =
    if
      executed < budget
      && Option.is_none (Run.status t.run)
      && (executed = 0 || Time_ns.O.(Clock.now () < until))
    then (
      Run.step t.run ~keys;
      go (executed + 1))
    else executed
  in
  go 0
;;

(* Draw what the instructions changed, and the status line if that changed. *)
let draw t ~keys ~stepped =
  let start = Clock.now () in
  if stepped then Display.refresh t.display;
  let running = Option.is_none (Run.status t.run) in
  (match Display.draw t.display ~status:(status_line t.run ~keys) ~repeat_status:running with
   | "" -> ()
   | changes -> Terminal.write changes);
  t.draw_time <- Time_ns.diff (Clock.now ()) start
;;

(* Take the keyboard's input until [until]. *)
let rec wait t ~until =
  let now = Clock.now () in
  Keyboard.expire t.keyboard ~now;
  if Time_ns.O.(now < until) && not (leaving t)
  then (
    let wake =
      Option.value_map (Keyboard.deadline t.keyboard) ~default:until ~f:(Time_ns.min until)
    in
    (match Terminal.read ~timeout:(Time_ns.diff wake now) with
     | Bytes bytes -> Keyboard.feed t.keyboard ~now:(Clock.now ()) bytes
     | Nothing -> ()
     | Closed -> t.closed <- true);
    wait t ~until)
;;

(* One frame after another from [start], until someone leaves. The instructions end a little
   before the frame does, in time for the draw. *)
let rec frames t ~start =
  let until = Time_ns.add start frame_time in
  if Terminal.resized () then Display.reset t.display;
  let keys = Keyboard.held t.keyboard ~now:(Clock.now ()) in
  let executed = advance t ~keys ~until:(Time_ns.sub until t.draw_time) in
  draw t ~keys ~stepped:(executed > 0);
  wait t ~until;
  if not (leaving t)
  then (
    (* A frame that overran does not make the next ones shorter to catch up. *)
    let late = Time_ns.O.(Clock.now () > until + frame_time) in
    frames t ~start:(if late then Clock.now () else until))
;;

let play ~max_steps ~hz =
  let t =
    { run = Run.create ~max_steps
    ; keyboard = Keyboard.create ()
    ; display = Display.create ()
    ; budget = Budget.create ~hz
    ; closed = false
    ; draw_time = Time_ns.Span.zero
    }
  in
  Display.refresh t.display;
  let%bind.Or_error () = Terminal.with_screen (fun () -> frames t ~start:(Clock.now ())) in
  if t.closed
  then Or_error.error_string "the terminal is gone"
  else (
    match Run.status t.run with
    | None -> Ok 0
    | Some status -> Ok (Run.Status.exit_code status))
;;

let run ({ image; max_steps; hz } : Options.t) =
  if not (Terminal.available ())
  then Or_error.error_string "interactive mode needs a terminal on standard input and output"
  else (
    Machine.start ();
    let%bind.Or_error () = Image.load image in
    play ~max_steps ~hz)
;;
