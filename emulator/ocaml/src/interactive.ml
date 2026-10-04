open! Import

module Options = struct
  type t =
    { image : Filename.t
    ; max_steps : int
    ; hz : int
    }
end

let frames_per_second = 30
let seconds_per_frame = 1. /. Float.of_int frames_per_second
let frame_time = Time_ns.Span.of_sec seconds_per_frame

(* How many instructions to run before each frame. *)
module Budget = struct
  type t =
    { hz : int
    ; carry : int
    }

  let create ~hz = ({ hz; carry = 0 } : t)

  (* [hz] a second makes [hz / frames_per_second] a frame, and the remainder is carried to the next
     frames so that the rate is exact. As many as fit if [hz] is 0. The budget of the next frame,
     and the budgets of those after it. *)
  let next t =
    match t.hz with
    | 0 -> Int.max_value, t
    | hz ->
      let carry = t.carry + (hz % frames_per_second) in
      let budget = (hz / frames_per_second) + (carry / frames_per_second) in
      budget, { t with carry = carry % frames_per_second }
  ;;
end

(* Why the play stops. *)
module Stop = struct
  type t =
    | Left
    | Interrupted
    | Terminal_gone
end

type t =
  { run : Run.t
  ; keyboard : Keyboard.t
  ; display : Display.t
  ; budget : Budget.t
  ; draw_time : Time_ns.Span.t (* What the last draw took. *)
  ; stop : Stop.t option (* None while the play goes on. *)
  }

let status_line run ~keys =
  let state = Run.status run |> Option.value_map ~default:"running" ~f:Run.Status.to_string in
  let pc = Machine.pc () |> Hex.word in
  let steps = Run.retired run in
  let held =
    List.map Keys.Line.all ~f:(fun line ->
      match Keys.state keys line with
      | Held -> Keys.Line.letter line
      | Released -> '-')
    |> String.of_char_list
  in
  [%string "%{state}  pc 0x%{pc}  steps %{steps#Int}  keys %{held}"]
;;

(* Run the instructions of one frame: as many as the budget allows, but none that start after
   [until], except the first. The state after them, and how many ran. *)
let advance t ~keys ~until =
  let budget, next_budget = Budget.next t.budget in
  let rec go run executed =
    match Run.status run with
    | Some _ -> run, executed
    | None ->
      if executed < budget && (executed = 0 || Time_ns.O.(Clock.now () < until))
      then (
        let run = Run.step run ~keys in
        go run (executed + 1))
      else run, executed
  in
  let run, executed = go t.run 0 in
  { t with run; budget = next_budget }, executed
;;

(* Draw what the [executed] instructions changed, and the status line if that changed. *)
let draw t ~keys ~executed =
  let start = Clock.now () in
  let display = if executed > 0 then Display.refresh t.display else t.display in
  let status = status_line t.run ~keys in
  let rewrite : Display.Status_rewrite.t =
    match Run.status t.run with
    | None -> Always
    | Some _ -> When_changed
  in
  let changes, display = Display.draw display ~status ~rewrite in
  (match changes with
   | "" -> ()
   | changes -> Terminal.write changes);
  let finish = Clock.now () in
  { t with display; draw_time = Time_ns.diff finish start }
;;

(* Why the keyboard or a signal stops the play, if it does. *)
let stop_reason keyboard : Stop.t option =
  match Keyboard.request keyboard, Terminal.interrupted () with
  | Leave, _ -> Some Left
  | Stay, Some _ -> Some Interrupted
  | Stay, None -> None
;;

(* Take the keyboard's input until [until], or until the play stops. *)
let rec wait t ~until =
  let now = Clock.now () in
  let keyboard = Keyboard.expire t.keyboard ~now in
  match stop_reason keyboard with
  | Some _ as stop -> { t with keyboard; stop }
  | None ->
    if Time_ns.O.(now < until)
    then (
      let wake =
        Keyboard.deadline keyboard |> Option.value_map ~default:until ~f:(Time_ns.min until)
      in
      let timeout = Time_ns.diff wake now in
      match Terminal.read ~timeout with
      | Bytes bytes ->
        let now = Clock.now () in
        let keyboard = Keyboard.feed keyboard ~now bytes in
        wait { t with keyboard } ~until
      | Nothing -> wait { t with keyboard } ~until
      | Closed -> { t with keyboard; stop = Some Terminal_gone })
    else { t with keyboard }
;;

(* One frame after another from [start], until the play stops. The instructions end a little
   before the frame does, in time for the draw. *)
let rec frames t ~start =
  let until = Time_ns.add start frame_time in
  let display =
    match Terminal.resized () with
    | Resized -> Display.reset t.display
    | Unchanged -> t.display
  in
  let now = Clock.now () in
  let keys = Keyboard.held t.keyboard ~now in
  let run_until = Time_ns.sub until t.draw_time in
  let t, executed = advance { t with display } ~keys ~until:run_until in
  let t = draw t ~keys ~executed |> wait ~until in
  match t.stop with
  | Some _ -> t
  | None ->
    (* A frame that overran does not make the next ones shorter to catch up. *)
    let now = Clock.now () in
    frames t ~start:(if Time_ns.O.(now > until + frame_time) then now else until)
;;

let play ~max_steps ~hz =
  let t =
    ({ run = Run.create ~max_steps
     ; keyboard = Keyboard.create ()
     ; display = Display.create ()
     ; budget = Budget.create ~hz
     ; draw_time = Time_ns.Span.zero
     ; stop = None
     }
     : t)
  in
  let%bind.Or_error t =
    Terminal.with_screen (fun () ->
      let start = Clock.now () in
      frames t ~start)
  in
  match t.stop with
  | Some Terminal_gone -> Or_error.error_string "the terminal is gone"
  | Some (Left | Interrupted) | None ->
    Run.status t.run |> Option.value_map ~default:0 ~f:Run.Status.exit_code |> Ok
;;

let run ({ image; max_steps; hz } : Options.t) =
  let%bind.Or_error () = Terminal.check () in
  Machine.start ();
  let%bind.Or_error () = Image.load image in
  play ~max_steps ~hz
;;
