open! Core

let print_all () =
  for word = 0 to 0xFFFF do
    printf "%04x %s\n" word (Machine.disasm word)
  done
;;
