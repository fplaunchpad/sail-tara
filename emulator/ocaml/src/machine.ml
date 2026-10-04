open! Import
module Sail = Libsail.Sail_lib

let bits ~width n =
  let width = Sail.Big_int.of_int width
  and n = Sail.Big_int.of_int n in
  Sail.get_slice_int width n Sail.Big_int.zero
;;

let to_int bits = bits |> Sail.uint |> Sail.Big_int.to_int

module Step = struct
  type t =
    | Retired
    | Stopped
    | Illegal
  [@@deriving sexp_of]

  let of_bits result =
    match to_int result with
    | 0 -> Retired
    | 1 -> Stopped
    | 2 -> Illegal
    | n -> raise_s [%message "host_step: unexpected result" (n : int)]
  ;;
end

module Pixel = struct
  type t =
    | Lit
    | Dark
  [@@deriving equal]
end

module Cpu = struct
  type t =
    | Running
    | Halted
end

let start () =
  Tara.zinitializze_registers ();
  Tara.zhost_reset ()
;;

let poke ~address value =
  let address = bits ~width:11 address
  and value = bits ~width:8 value in
  Tara.zhost_poke address value
;;

let peek ~address = bits ~width:11 address |> Tara.zhost_peek |> to_int

let pixel ~x ~y =
  let x = bits ~width:6 x
  and y = bits ~width:6 y in
  if Tara.zhost_pixel x y then Pixel.Lit else Dark
;;

let pc () = Tara.zhost_pc () |> to_int
let cpu () = if Tara.zhost_halted () then Cpu.Halted else Running
let step ~keys = bits ~width:5 keys |> Tara.zhost_step |> Step.of_bits
let disasm word = bits ~width:16 word |> Tara.zhost_disasm
let trace () = Tara.zhost_trace ()
let dump () = Tara.zhost_dump ()
