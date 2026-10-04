open! Core

let parse text ~what ~is_digit ~prefix =
  if String.is_empty text || not (String.for_all text ~f:is_digit)
  then Or_error.error_s [%message [%string "expected %{what}"] text]
  else (
    match [%string "%{prefix}%{text}"] |> Int.of_string_opt with
    | Some n -> Ok n
    | None -> Or_error.error_s [%message "number too large" text])
;;

let decimal_digits text ~what = parse text ~what ~is_digit:Char.is_digit ~prefix:""
let decimal text = decimal_digits text ~what:"decimal digits"

let decimal_or_hex text =
  match String.chop_prefix text ~prefix:"0x", String.chop_prefix text ~prefix:"0X" with
  | Some digits, _ | None, Some digits ->
    parse digits ~what:"hex digits after 0x" ~is_digit:Char.is_hex_digit ~prefix:"0x"
  | None, None -> decimal_digits text ~what:"decimal digits, or 0x and hex digits"
;;
