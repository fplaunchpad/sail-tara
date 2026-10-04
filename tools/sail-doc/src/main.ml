open Core
open Libsail

(* Sail's options are Arg specifications, which can only set references. *)
let decode = ref "decode"
let assembly = ref "assembly"

let options =
  [ ( Flag.create ~prefix:[ "doc-tables" ] ~arg:"NAME" "decode"
    , Arg.Set_string decode
    , "the decode function (default decode)" )
  ; ( Flag.create ~prefix:[ "doc-tables" ] ~arg:"NAME" "assembly"
    , Arg.Set_string assembly
    , "the mapping of instructions to assembly text (default assembly)" )
  ]
;;

let run output (state : Interactive.State.istate) =
  match output with
  | None -> Sail_ast.fail_at Parse_ast.Unknown "--doc-tables writes to the file given with -o"
  | Some path ->
    let json =
      Instruction_set.read ~ast:state.ast ~env:state.env ~decode:!decode ~assembly:!assembly
      |> Instruction_set.yojson_of_t
      |> Yojson.Safe.pretty_to_string
    in
    Out_channel.write_all path ~data:[%string "%{json}\n"]
;;

let () =
  ignore
    (Target.register
       ~name:"doc-tables"
       ~flag:"doc-tables"
       ~description:"Write the instruction set's encodings and syntax as JSON"
       ~options
       ~skip_initial_rewrite:true
       run
     : Target.target)
;;
