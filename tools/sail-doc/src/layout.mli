open Libsail

type t = Metadata.t

val extract
  :  ast:Type_check.typed_ast
  -> env:Type_check.Env.t
  -> constants:Constant.t
  -> decode_name:string
  -> encode_name:string
  -> assembly_name:string
  -> t
