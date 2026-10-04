open! Import

let size = 64
let base = 0x600
let pixels_per_byte = 8
let bytes_per_row = size / pixels_per_byte

type t =
  { bytes : int array array (* The framebuffer's bytes, by row (y) and byte. *)
  ; pixels : Machine.Pixel.t array array (* By row (y) and column (x). *)
  }

let read_bytes () =
  Array.init size ~f:(fun y ->
    Array.init bytes_per_row ~f:(fun byte ->
      Machine.peek ~address:(base + (y * bytes_per_row) + byte)))
;;

let read () =
  let bytes = read_bytes () in
  let pixels = Array.init size ~f:(fun y -> Array.init size ~f:(fun x -> Machine.pixel ~x ~y)) in
  ({ bytes; pixels } : t)
;;

(* The pixels of row [y], given its bytes now: those of [before] where the byte that holds a pixel
   has not changed, and the others read from the model, which knows their bit order. *)
let refresh_row (before : t) ~y ~bytes =
  if Array.equal Int.equal bytes before.bytes.(y)
  then before.pixels.(y)
  else
    Array.init size ~f:(fun x ->
      let byte = x / pixels_per_byte in
      if bytes.(byte) = before.bytes.(y).(byte) then before.pixels.(y).(x) else Machine.pixel ~x ~y)
;;

let refresh before =
  let bytes = read_bytes () in
  let pixels = Array.init size ~f:(fun y -> refresh_row before ~y ~bytes:bytes.(y)) in
  ({ bytes; pixels } : t)
;;

let pixel t ~x ~y = t.pixels.(y).(x)
