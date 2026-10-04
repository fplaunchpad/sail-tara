open! Import

let print_all () =
  for word = 0 to 0xFFFF do
    let hex = Hex.word word in
    let assembly = Machine.disasm word in
    Out_channel.output_string stdout [%string "%{hex} %{assembly}\n"]
  done
;;
