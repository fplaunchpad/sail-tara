open Core
open Libsail
open Extraction.Ast

module Expression : sig
  type t =
    | Value of
        { text : string
        ; width : int option
        }
    | Call of
        { name : string
        ; arguments : t list
        ; width : int option
        ; notation : string option
        }
    | Binary of
        { operator : string
        ; left : t
        ; right : t
        ; width : int option
        }
    | Slice of
        { value : t
        ; high : t
        ; low : t option
        ; width : int option
        }
    | Choice of
        { condition : t
        ; yes : t
        ; no : t
        ; width : int option
        }
  [@@deriving yojson_of]
end

type t =
  | Evaluate of { value : Expression.t }
  | Assign of
      { target : Expression.t
      ; value : Expression.t
      }
  | Bind of
      { name : string
      ; value : Expression.t
      ; body : t list
      }
  | Branch of
      { condition : Expression.t
      ; yes : t list
      ; no : t list
      }
[@@deriving yojson_of]

val expression
  :  env:Type_check.Env.t
  -> notation:Notation.t
  -> bindings:string String.Map.t
  -> Type_check.tannot exp
  -> Expression.t

val statements
  :  env:Type_check.Env.t
  -> notation:Notation.t
  -> bindings:string String.Map.t
  -> Type_check.tannot exp
  -> t list

val calls : t -> string list
