open! Import

let columns = Framebuffer.size
let rows = Framebuffer.size / 2
let upper_half_block = "\u{2580}"
let lit = ({ red = 0xFF; green = 0xB0; blue = 0x00 } : Ansi.Colour.t)
let dark = ({ red = 0x1C; green = 0x1C; blue = 0x1C } : Ansi.Colour.t)

module Status_rewrite = struct
  type t =
    | Always
    | When_changed
end

(* What a character shows: the upper pixel as its foreground, and the lower as its background. *)
module Cell = struct
  type t =
    { upper : Machine.Pixel.t
    ; lower : Machine.Pixel.t
    }
  [@@deriving equal]

  let read framebuffer ~row ~column =
    let upper = Framebuffer.size - 1 - (2 * row) in
    ({ upper = Framebuffer.pixel framebuffer ~x:column ~y:upper
     ; lower = Framebuffer.pixel framebuffer ~x:column ~y:(upper - 1)
     }
     : t)
  ;;

  let colour : Machine.Pixel.t -> Ansi.Colour.t = function
    | Lit -> lit
    | Dark -> dark
  ;;

  let colours ~upper ~lower =
    let foreground = colour upper
    and background = colour lower in
    Ansi.colours ~foreground ~background
  ;;

  let lit_on_lit = colours ~upper:Lit ~lower:Lit
  let lit_on_dark = colours ~upper:Lit ~lower:Dark
  let dark_on_lit = colours ~upper:Dark ~lower:Lit
  let dark_on_dark = colours ~upper:Dark ~lower:Dark

  (* The control sequence that sets the colours to show the cell, built once. *)
  let set_colours : t -> string = function
    | { upper = Lit; lower = Lit } -> lit_on_lit
    | { upper = Lit; lower = Dark } -> lit_on_dark
    | { upper = Dark; lower = Lit } -> dark_on_lit
    | { upper = Dark; lower = Dark } -> dark_on_dark
  ;;
end

(* What the terminal shows. *)
module Shown = struct
  type t =
    { cells : Cell.t array array (* By row and column. *)
    ; status : string
    }
end

type t =
  { framebuffer : Framebuffer.t
  ; shown : Shown.t option (* None: nothing is known, as before the first draw. *)
  }

let create () = ({ framebuffer = Framebuffer.read (); shown = None } : t)
let reset t = { t with shown = None }
let refresh t = { t with framebuffer = Framebuffer.refresh t.framebuffer }

(* What painting has left the terminal set to: the column the cursor is in, if it is on a row being
   painted, which is the one after the last character drawn; and the cell whose colours are set. *)
module Pen = struct
  type t =
    { cursor : int option
    ; colours : Cell.t option
    }

  let blank = ({ cursor = None; colours = None } : t)
end

(* Paint [cell] at [column] of [row] (both from 0) with the pen as the last painting left it. *)
let paint out ~row ~column (pen : Pen.t) cell =
  (match pen.cursor with
   | Some cursor when cursor = column -> ()
   | Some _ | None -> Ansi.move_to ~row:(row + 1) ~column:(column + 1) |> Buffer.add_string out);
  (match pen.colours with
   | Some colours when Cell.equal colours cell -> ()
   | Some _ | None -> Cell.set_colours cell |> Buffer.add_string out);
  Buffer.add_string out upper_half_block;
  ({ cursor = Some (column + 1); colours = Some cell } : Pen.t)
;;

(* Paint the cells of [row] that differ from [shown], the row as the terminal shows it, if known. *)
let paint_row out ~row (pen : Pen.t) ~shown cells_in_row =
  let pen = { pen with cursor = None } in
  Array.foldi cells_in_row ~init:pen ~f:(fun column pen cell ->
    match shown with
    | Some shown when Cell.equal cell shown.(column) -> pen
    | Some _ | None -> paint out ~row ~column pen cell)
;;

let status_line status =
  let home = Ansi.move_to ~row:(rows + 1) ~column:1 in
  [%string "%{home}%{status}%{Ansi.erase_to_end_of_line}"]
;;

let draw t ~status ~(rewrite : Status_rewrite.t) =
  let cells =
    Array.init rows ~f:(fun row ->
      Array.init columns ~f:(fun column -> Cell.read t.framebuffer ~row ~column))
  in
  let out = Buffer.create 4096 in
  (match t.shown with
   | None -> Buffer.add_string out Ansi.clear_screen
   | Some _ -> ());
  let pen =
    Array.foldi cells ~init:Pen.blank ~f:(fun row pen cells_in_row ->
      let shown = Option.map t.shown ~f:(fun (shown : Shown.t) -> shown.cells.(row)) in
      paint_row out ~row pen ~shown cells_in_row)
  in
  (match pen.colours with
   | Some _ -> Buffer.add_string out Ansi.reset_colours
   | None -> ());
  (match rewrite, t.shown with
   | When_changed, Some ({ status = shown; _ } : Shown.t) when String.equal shown status -> ()
   | Always, _ | When_changed, _ -> status_line status |> Buffer.add_string out);
  let shown = ({ cells; status } : Shown.t) in
  Buffer.contents out, ({ t with shown = Some shown } : t)
;;
