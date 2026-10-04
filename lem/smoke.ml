(* Executable smoke test of the Lem backend: `just lem smoke`. It runs the hardware manual's
   Fibonacci program on the model that Lem extracted to OCaml, from power-on until the CPU halts,
   prints the final state as the emulators do (minus the memory) and compares it with the manual's.
   A mismatch shows the expected value and fails the run.

   The model's functions are computations of Sail's prompt monad. Sail's Lem library lifts them to
   a state monad (Sail2_state_lifting), but Lem cannot extract that to OCaml: it chooses from
   `universal`, the set of all values of a type. So [Machine.run] interprets them directly. *)

open! Core
open Tara_lem

(** The model's bit vectors are lists of bits, most significant first. *)
module Bits = struct
  let of_int ~width value =
    List.init width ~f:(fun position ->
      if (value lsr (width - 1 - position)) land 1 = 1 then Sail2_values.B1 else B0)
  ;;

  let to_int bits =
    List.fold bits ~init:0 ~f:(fun value (bit : Sail2_values.bitU) ->
      match bit with
      | B0 -> 2 * value
      | B1 -> (2 * value) + 1
      | BU -> raise_s [%message "undefined bit"])
  ;;
end

(** How a run ends, and its name in the emulators' status line. *)
module Ending = struct
  type t =
    | Halted
    | Limit
    | Illegal
  [@@deriving string ~capitalize:"snake_case"]
end

module Machine = struct
  type t = Tara_types.regstate

  (** What each of the model's functions becomes: a tree of register reads and writes. *)
  module Computation = struct
    type 'a t = (Tara_types.register_value, 'a, unit) Sail2_prompt_monad.monad
  end

  (** Run a computation of the model on a register state: its result and the state after it. The
      model's functions only read and write registers (the memory is one of them) and choose values
      for undefined registers, which become zero and false. *)
  let rec run state (computation : 'a Computation.t) : 'a * t =
    match computation with
    | Done result -> result, state
    | Read_reg (name, continue) ->
      (match Tara_types.get_regval name state with
       | Some value -> run state (continue value)
       | None -> raise_s [%message "no such register" name])
    | Write_reg (name, value, rest) ->
      (match Tara_types.set_regval name value state with
       | Some state -> run state rest
       | None -> raise_s [%message "no such register" name])
    | Choose (_, continue) -> run state (continue (Regval_bool false))
    | Print (message, rest) ->
      print_endline message;
      run state rest
    | Fail message -> raise_s [%message "the model failed" message]
    | Exception () -> raise_s [%message "the model raised an exception"]
    | Read_mem _
    | Read_memt _
    | Write_ea _
    | Excl_res _
    | Write_mem _
    | Write_memt _
    | Footprint _
    | Barrier _ -> raise_s [%message "the model accessed memory outside its registers"]
  ;;

  (* Grouped by type, the generated register state has no initial value: start from one in which
     no register has a value, for the model's initialisation to define. *)
  let unset _ = raise_s [%message "register read before its initialisation"]

  let blank : t =
    { bitvector_16_reg = unset
    ; bitvector_5_reg = unset
    ; bool_reg = unset
    ; vector_2048_bitvector_8_reg = unset
    ; vector_8_bitvector_16_reg = unset
    }
  ;;

  (** Power-on: the model initialises every register to an undefined value, so the registers and
      memory are zero, PC is 0 and the CPU is running. *)
  let power_on () = Tara.sail_model_init () |> run blank |> snd

  (** Store [words] from address 0 on, with the model's [write_word]. *)
  let load state ~words =
    List.foldi words ~init:state ~f:(fun index state word ->
      let address = Bits.of_int ~width:16 (2 * index)
      and value = Bits.of_int ~width:16 word in
      Tara.write_word address value |> run state |> snd)
  ;;

  (** Step until the CPU halts, fetches an illegal opcode or [max_steps] instructions retire: how
      the run ended, the number of instructions retired and the final state. *)
  let run_program state ~max_steps =
    let rec go state retired =
      if retired = max_steps
      then Ending.Limit, retired, state
      else (
        match Bits.of_int ~width:5 0 |> Tara.step |> run state with
        | Retired (), state -> go state (retired + 1)
        | Stopped (), state -> Ending.Halted, retired, state
        | Illegal _, state -> Ending.Illegal, retired, state)
    in
    go state 0
  ;;

  let pc state =
    match Tara_types.get_regval "PC" state with
    | Some (Regval_bitvector_16 bits) -> Bits.to_int bits
    | _ -> raise_s [%message "PC is not a 16-bit register"]
  ;;

  let register state index =
    Bits.of_int ~width:3 index |> Tara.rX |> run state |> fst |> Bits.to_int
  ;;
end

(** The program from the manual, as big-endian words loaded at address 0, with its assembly. *)
let fibonacci =
  [ 0x1a00 (* LIL R2, 0 *)
  ; 0x1b01 (* LIL R3, 1 *)
  ; 0x1d0a (* LIL R5, 10 *)
  ; 0xa505 (* loop: BZ R5, done *)
  ; 0x4c4c (* ADD R4, R2, R3 *)
  ; 0x1260 (* MOV R2, R3 *)
  ; 0x1380 (* MOV R3, R4 *)
  ; 0x5dff (* ADDI R5, -1 *)
  ; 0xb7fa (* JMP loop *)
  ; 0x1640 (* done: MOV R6, R2 *)
  ; 0x0800 (* HLT *)
  ]
;;

(** More instructions than the program retires, so a runaway program fails instead of hanging. *)
let max_steps = 1000

(** The final state the manual gives: 66 instructions retire, PC is just past the HLT, F(10) is in
    R2 and R6, F(11) in R3 and R4, and the other registers are still zero. *)
module Expected = struct
  let steps = 66
  let pc = 0x0016

  let register = function
    | 2 | 6 -> 0x0037
    | 3 | 4 -> 0x0059
    | _ -> 0x0000
  ;;
end

(** Print one field of the final state, with the expected value if it differs. *)
let check name ~actual ~expected =
  let matches = String.equal actual expected in
  print_endline
    (if matches
     then [%string "%{name} %{actual}"]
     else [%string "%{name} %{actual} (expected %{expected})"]);
  matches
;;

let () =
  let ending, steps, state =
    Machine.power_on () |> Machine.load ~words:fibonacci |> Machine.run_program ~max_steps
  in
  let hex = sprintf "0x%04x" in
  let register index =
    let actual = Machine.register state index |> hex
    and expected = Expected.register index |> hex in
    [%string "r%{index#Int}"], actual, expected
  in
  let fields =
    [ "status", Ending.to_string ending, Ending.to_string Halted
    ; "steps", Int.to_string steps, Int.to_string Expected.steps
    ; "pc", Machine.pc state |> hex, hex Expected.pc
    ]
    @ List.init 8 ~f:register
  in
  let mismatches =
    List.count fields ~f:(fun (name, actual, expected) -> not (check name ~actual ~expected))
  in
  if mismatches > 0 then Stdlib.exit 1
;;
