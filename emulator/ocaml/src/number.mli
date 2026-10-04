(** Integers as the command line and the text files write them: digits only, with no sign, no
    underscores and no octal. *)

open! Core

(** Decimal digits; leading zeros are allowed. *)
val decimal : string -> int Or_error.t

(** Decimal digits, or [0x] or [0X] followed by hex digits. *)
val decimal_or_hex : string -> int Or_error.t
