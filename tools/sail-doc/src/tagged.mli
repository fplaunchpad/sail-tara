(** [json] with a [kind] field first, which tells apart the cases of a variant whose cases are
    objects. *)
val json : kind:string -> Yojson.Safe.t -> Yojson.Safe.t
