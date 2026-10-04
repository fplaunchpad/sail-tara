(** Numbers in hex, as the emulators print them. *)

(** The low 16 bits of a number as four lowercase hex digits: [word 0x1bc] is ["01bc"]. *)
val word : int -> string
