(** Core, without printf: text is built with [%string] and written with Out_channel. Naming one of
    the functions or modules at the end is a compile error, from [-alert ++deprecated] in
    [src/dune]. Every module of the emulator opens this instead of Core. *)

include module type of struct
    include Core
  end
  with module Printf := Core.Printf

val printf : [ `Banned ] [@@deprecated "[since 2026-10] use [%string] and Out_channel, not printf"]

val eprintf : [ `Banned ]
[@@deprecated "[since 2026-10] use [%string] and Out_channel, not eprintf"]

val sprintf : [ `Banned ] [@@deprecated "[since 2026-10] use [%string], not sprintf"]
val ksprintf : [ `Banned ] [@@deprecated "[since 2026-10] use [%string], not ksprintf"]

val failwithf : [ `Banned ]
[@@deprecated "[since 2026-10] use [%string] and failwith, not failwithf"]

module Printf : sig end
[@@deprecated "[since 2026-10] use [%string] and Out_channel, not the Printf module"]

module Format : sig end
[@@deprecated "[since 2026-10] use [%string] and Out_channel, not the Format module"]
