open! Import

let digit value = "0123456789abcdef".[value land 0xF]
let word value = String.init 4 ~f:(fun index -> value lsr (4 * (3 - index)) |> digit)
