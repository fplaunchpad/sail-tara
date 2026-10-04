open Core
open Libsail

let decode_name = ref None
let encode_name = ref None
let assembly_name = ref None
let captured_ast = ref None

let name_option name value =
  ( Flag.create ~prefix:[ "doc-tables" ] ~arg:"NAME" name
  , Arg.String (fun setting -> value := Some setting)
  , [%string "Name of the %{name} definition"] )
;;

let options =
  [ name_option "decode" decode_name
  ; name_option "encode" encode_name
  ; name_option "assembly" assembly_name
  ]
;;

let required_name location option name =
  match !option with
  | Some value -> value
  | None -> raise (Reporting.err_general location [%string "--doc-tables-%{name} is required"])
;;

let write_json output_path json =
  let temporary_path = [%string "%{output_path}.tmp"] in
  try
    Out_channel.write_all temporary_path ~data:[%string "%{Yojson.Safe.pretty_to_string json}\n"];
    Stdlib.Sys.rename temporary_path output_path
  with
  | exn ->
    (try Stdlib.Sys.remove temporary_path with
     | _ -> ());
    raise
      (Reporting.err_general
         Parse_ast.Unknown
         [%string "cannot write doc tables to %{output_path}: %{Exn.to_string exn}"])
;;

let run output_path (state : Interactive.State.istate) =
  let output_path =
    match output_path with
    | Some path -> path
    | None ->
      raise (Reporting.err_general Parse_ast.Unknown "-o OUTPUT is required for --doc-tables")
  in
  let ast, env =
    match !captured_ast with
    | Some pair -> pair
    | None -> raise (Reporting.err_general Parse_ast.Unknown "typed Sail AST was not captured")
  in
  let decode = required_name Parse_ast.Unknown decode_name "decode" in
  let encode = required_name Parse_ast.Unknown encode_name "encode" in
  let assembly = required_name Parse_ast.Unknown assembly_name "assembly" in
  let constants =
    match Constant.create state with
    | Ok constants -> constants
    | Error error -> raise (Reporting.err_general Parse_ast.Unknown (Error.to_string_hum error))
  in
  let layout =
    Layout.extract
      ~ast
      ~env
      ~constants
      ~decode_name:decode
      ~encode_name:encode
      ~assembly_name:assembly
  in
  write_json output_path (Metadata.yojson_of_t layout)
;;

let () =
  ignore
    (Target.register
       ~name:"doc-tables"
       ~flag:"doc-tables"
       ~description:"Extract instruction table metadata from typed Sail definitions"
       ~options
       ~skip_initial_rewrite:true
       ~pre_rewrites_hook:(fun ast _ env -> captured_ast := Some (ast, env))
       run
     : Target.target)
;;
