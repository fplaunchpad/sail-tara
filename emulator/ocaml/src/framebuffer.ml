open! Core

let size = 64
let base = 0x600
let pixels_per_byte = 8
let bytes_per_row = size / pixels_per_byte

type t =
  { seen : int array array
    (* The last value of each framebuffer byte, by row and byte; -1 before the first. *)
  ; pixels : bool array array (* By row (y) and column (x). *)
  }

let create () =
  { seen = Array.make_matrix ~dimx:size ~dimy:bytes_per_row (-1)
  ; pixels = Array.make_matrix ~dimx:size ~dimy:size false
  }
;;

(* The pixels of row [y] that its byte [byte] holds are read from the model, which knows their bit
   order. *)
let read_byte t ~y ~byte =
  let first = byte * pixels_per_byte in
  for x = first to first + pixels_per_byte - 1 do
    t.pixels.(y).(x) <- Machine.pixel ~x ~y
  done
;;

let refresh t =
  Array.iteri t.seen ~f:(fun y row ->
    Array.iteri row ~f:(fun byte seen ->
      let value = Machine.peek ~address:(base + (y * bytes_per_row) + byte) in
      if value <> seen
      then (
        row.(byte) <- value;
        read_byte t ~y ~byte)))
;;

let pixel t ~x ~y = t.pixels.(y).(x)
