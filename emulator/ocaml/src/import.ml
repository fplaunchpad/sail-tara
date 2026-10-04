include Core

(* The values and modules that the interface deprecates. Nothing can use them: they are not the
   functions they replace. *)

let printf = `Banned
let eprintf = `Banned
let sprintf = `Banned
let ksprintf = `Banned
let failwithf = `Banned

module Printf = struct end
module Format = struct end
