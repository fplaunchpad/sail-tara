open Core
open Libsail

(* Sail's options are Arg specifications, which can only set references. *)
let encdec = ref "encdec"
let assembly = ref "assembly"
let execute = ref "execute"
let complete = ref false
let examples = ref None

let option name reference description =
  ( Flag.create ~prefix:[ "doc-tables" ] ~arg:"NAME" name
  , Arg.Set_string reference
  , [%string "%{description} (default %{!reference})"] )
;;

let options =
  [ option "encdec" encdec "the mapping of instructions to words"
  ; option "assembly" assembly "the mapping of instructions to assembly text"
  ; option "execute" execute "the function that carries out an instruction"
  ; ( Flag.create ~prefix:[ "doc-tables" ] "complete"
    , Arg.Set complete
    , "Require documentation for every encoding" )
  ; ( Flag.create ~prefix:[ "doc-tables" ] ~arg:"FILE" "examples"
    , Arg.String (fun path -> examples := Some path)
    , "Evaluate validation inputs from a test fixture" )
  ]
;;

let run output (state : Interactive.State.istate) =
  match output with
  | None -> Sail_ast.fail_at Parse_ast.Unknown "--doc-tables writes to the file given with -o"
  | Some path ->
    let json =
      Instruction_set.read
        ~state
        ~encdec:!encdec
        ~assembly:!assembly
        ~execute:!execute
        ~complete:!complete
        ~examples:!examples
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
       ~description:"Write the instruction set's encodings, syntax and execution as JSON"
       ~options
       ~skip_initial_rewrite:true
       run
     : Target.target)
;;
