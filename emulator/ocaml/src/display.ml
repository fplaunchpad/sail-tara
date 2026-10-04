open! Core

let columns = Framebuffer.size
let rows = Framebuffer.size / 2
let upper_half_block = "\u{2580}"
let lit = { Ansi.Colour.red = 0xFF; green = 0xB0; blue = 0x00 }
let dark = { Ansi.Colour.red = 0x1C; green = 0x1C; blue = 0x1C }

(* What a character shows: the upper pixel as its foreground, bit 0, and the lower as its background,
   bit 1. *)
module Cell = struct
  type t = int

  (* Not a cell that any pixels make: what a character shows before it is drawn. *)
  let unknown = -1

  (* The control sequence that sets the colours to show each cell. *)
  let set_colours =
    let colour cell bit = if cell land bit <> 0 then lit else dark in
    Array.init 4 ~f:(fun cell ->
      Ansi.colours ~foreground:(colour cell 1) ~background:(colour cell 2))
  ;;

  let read framebuffer ~row ~column =
    let upper = Framebuffer.size - 1 - (2 * row) in
    let pixel y = Framebuffer.pixel framebuffer ~x:column ~y |> Bool.to_int in
    pixel upper lor (pixel (upper - 1) lsl 1)
  ;;
end

type t =
  { framebuffer : Framebuffer.t
  ; drawn : Cell.t array array (* By row and column. *)
  ; mutable status : string (* The status line shown, or "" if none. *)
  ; mutable clear : bool (* The screen is to be cleared before the next draw. *)
  ; out : Buffer.t
  }

let create () =
  { framebuffer = Framebuffer.create ()
  ; drawn = Array.make_matrix ~dimx:rows ~dimy:columns Cell.unknown
  ; status = ""
  ; clear = true
  ; out = Buffer.create 4096
  }
;;

let reset t =
  Array.iter t.drawn ~f:(fun row -> Array.fill row ~pos:0 ~len:columns Cell.unknown);
  t.status <- "";
  t.clear <- true
;;

let refresh t = Framebuffer.refresh t.framebuffer

(* Draw the characters of [row] (from 0) that are not as the framebuffer says. [colours] is the
   cell that the terminal's colours show, and is kept up to date. *)
let draw_row t ~row ~colours =
  (* The column after the last character drawn, or -1 if none. *)
  let cursor = ref (-1) in
  for column = 0 to columns - 1 do
    let cell = Cell.read t.framebuffer ~row ~column in
    if cell <> t.drawn.(row).(column)
    then (
      t.drawn.(row).(column) <- cell;
      if !cursor <> column
      then Ansi.move_to ~row:(row + 1) ~column:(column + 1) |> Buffer.add_string t.out;
      if cell <> !colours
      then (
        Buffer.add_string t.out Cell.set_colours.(cell);
        colours := cell);
      Buffer.add_string t.out upper_half_block;
      cursor := column + 1)
  done
;;

let draw t ~status ~repeat_status =
  Buffer.clear t.out;
  if t.clear
  then (
    Buffer.add_string t.out Ansi.clear_screen;
    t.clear <- false);
  let colours = ref Cell.unknown in
  for row = 0 to rows - 1 do
    draw_row t ~row ~colours
  done;
  if !colours <> Cell.unknown then Buffer.add_string t.out Ansi.reset_colours;
  if repeat_status || not (String.equal status t.status)
  then (
    t.status <- status;
    Ansi.move_to ~row:(rows + 1) ~column:1 |> Buffer.add_string t.out;
    Buffer.add_string t.out status;
    Buffer.add_string t.out Ansi.erase_to_end_of_line);
  Buffer.contents t.out
;;
