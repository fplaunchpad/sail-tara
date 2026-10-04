open! Core
module Sail = Libsail.Sail_lib

let bits ~width n =
  Sail.get_slice_int (Sail.Big_int.of_int width) (Sail.Big_int.of_int n) Sail.Big_int.zero
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

let start () =
  Tara.zinitializze_registers ();
  Tara.zhost_reset ()
;;

let poke ~address value = Tara.zhost_poke (bits ~width:11 address) (bits ~width:8 value)
let peek ~address = bits ~width:11 address |> Tara.zhost_peek |> to_int
let pixel ~x ~y = Tara.zhost_pixel (bits ~width:6 x) (bits ~width:6 y)
let pc () = Tara.zhost_pc () |> to_int
let halted () = Tara.zhost_halted ()
let step ~keys = bits ~width:5 keys |> Tara.zhost_step |> Step.of_bits
let disasm word = bits ~width:16 word |> Tara.zhost_disasm
let trace () = Tara.zhost_trace ()
let dump () = Tara.zhost_dump ()
