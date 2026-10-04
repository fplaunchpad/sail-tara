open! Core
module Sail = Libsail.Sail_lib

let bits ~width n =
  Sail.get_slice_int (Sail.Big_int.of_int width) (Sail.Big_int.of_int n) Sail.Big_int.zero
;;

module Step = struct
  type t =
    | Retired
    | Stopped
    | Illegal
  [@@deriving sexp_of]

  let of_bits result =
    match result |> Sail.uint |> Sail.Big_int.to_int with
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
let halted () = Tara.zhost_halted ()
let step ~keys = bits ~width:5 keys |> Tara.zhost_step |> Step.of_bits
let trace () = Tara.zhost_trace ()
let dump () = Tara.zhost_dump ()
