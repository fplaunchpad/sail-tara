(** The disassembler: the model's assembly syntax for every instruction word. *)

(** Print a line [WWWW TEXT] for every word from 0000 to ffff, in order: the word in hex and its
    assembly text, [illegal] for an unassigned opcode. *)
val print_all : unit -> unit
