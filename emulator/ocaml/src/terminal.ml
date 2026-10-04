open! Import
module Terminal_io = Core_unix.Terminal_io

let check () =
  if Core_unix.isatty Core_unix.stdin && Core_unix.isatty Core_unix.stdout
  then Ok ()
  else Or_error.error_string "play needs a terminal on standard input and output"
;;

let wait_until_writable () =
  Core_unix.select ~restart:true ~read:[] ~write:[ Core_unix.stdout ] ~except:[] ~timeout:`Never ()
  |> (ignore : Core_unix.Select_fds.t -> unit)
;;

(* Straight to the terminal, with nothing left in a buffer if the terminal has gone away. *)
let write text =
  let rec go ~pos =
    if pos < String.length text
    then (
      let len = String.length text - pos in
      match Core_unix.single_write_substring Core_unix.stdout ~restart:true ~buf:text ~pos ~len with
      | written -> go ~pos:(pos + written)
      | exception Core_unix.Unix_error ((EAGAIN | EWOULDBLOCK), _, _) ->
        wait_until_writable ();
        go ~pos)
  in
  go ~pos:0
;;

module Input = struct
  type t =
    | Bytes of string
    | Nothing
    | Closed
end

let read ~timeout =
  let timeout = if Time_ns.Span.(timeout > zero) then `After timeout else `Immediately in
  let ready =
    Core_unix.select ~restart:true ~read:[ Core_unix.stdin ] ~write:[] ~except:[] ~timeout ()
  in
  match ready.read with
  | [] -> Input.Nothing
  | _ :: _ ->
    let buf = Bytes.create 256 in
    (match Core_unix.read ~restart:true Core_unix.stdin ~buf with
     | 0 -> Closed
     | length -> Bytes (Bytes.To_string.sub buf ~pos:0 ~len:length)
     | exception Core_unix.Unix_error (EIO, _, _) -> Closed)
;;

(* A signal handler can only change a global; the first signal that asked the program to stop. *)
let received : Signal.t option ref = ref None
let interrupted () = !received

module Size_change = struct
  type t =
    | Resized
    | Unchanged
end

(* Set by the handler of SIGWINCH, a global because a signal handler can only change one. *)
let size_change = ref Size_change.Unchanged

let resized () =
  let change = !size_change in
  size_change := Unchanged;
  change
;;

(* The signals that end the program. A signal that arrives again ends it as it would have, so that
   a program that does not answer the first can still be stopped. *)
let ending = [ Signal.hup; Signal.int; Signal.term ]

let note_ending signal =
  received := Some signal;
  Signal.Expert.set signal `Default
;;

let resize = Signal.of_caml_int Stdlib.Sys.sigwinch

(* Handle [signal] with [f], unless it is being ignored, as it is for a program started by nohup:
   that stays so. Returns how the signal was handled before. *)
let handle signal ~f =
  let before = Signal.Expert.signal signal (`Handle f) in
  (match before with
   | `Ignore -> Signal.Expert.set signal `Ignore
   | `Default | `Handle _ -> ());
  signal, before
;;

let raw (settings : Terminal_io.t) =
  { settings with
    c_echo = false
  ; c_icanon = false
  ; c_isig = false
  ; c_ixon = false
  ; c_vmin = 1
  ; c_vtime = 0
  }
;;

(* Undo what [with_screen] did. Each step is tried, whatever the ones before it did: the
   terminal may be gone. *)
let restore settings =
  let steps =
    [ (fun () ->
        write [%string "%{Ansi.reset_colours}%{Ansi.show_cursor}%{Ansi.leave_alternate_screen}"])
    ; (fun () -> Terminal_io.tcsetattr settings Core_unix.stdin ~mode:TCSAFLUSH)
    ]
  in
  List.iter steps ~f:(fun step -> Or_error.try_with step |> (ignore : unit Or_error.t -> unit))
;;

let run_on_screen settings f =
  let handled =
    handle resize ~f:(fun _ -> size_change := Resized) :: List.map ending ~f:(handle ~f:note_ending)
  in
  Exn.protect
    ~f:(fun () ->
      let raw_settings = raw settings in
      Terminal_io.tcsetattr raw_settings Core_unix.stdin ~mode:TCSAFLUSH;
      write [%string "%{Ansi.enter_alternate_screen}%{Ansi.hide_cursor}"];
      f ())
    ~finally:(fun () ->
      restore settings;
      List.iter handled ~f:(fun (signal, before) -> Signal.Expert.set signal before))
;;

let with_screen f =
  let settings = Terminal_io.tcgetattr Core_unix.stdin in
  let result =
    match run_on_screen settings f with
    | result -> Ok result
    | exception Core_unix.Unix_error (error, syscall, _) ->
      let message = Core_unix.Error.message error in
      Or_error.error_string [%string "cannot use the terminal: %{syscall}: %{message}"]
  in
  interrupted ()
  |> Option.iter ~f:(fun signal ->
    let pid = Core_unix.getpid () in
    Signal_unix.send_exn signal (`Pid pid));
  result
;;
