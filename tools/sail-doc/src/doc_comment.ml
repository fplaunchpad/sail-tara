open Core
open Libsail
open Extraction.Ast

module Entry = struct
  type t =
    { name : string
    ; text : string
    }
end

module Note = struct
  type t =
    { category : string
    ; text : string
    }
end

type t =
  { body : string
  ; brief : string option
  ; parameters : Entry.t list
  ; notes : Note.t list
  ; related : string list
  ; notation : string option
  ; id : string option
  ; anchors : Entry.t list
  }

module Line = struct
  type t =
    | Text of string
    | Marker of string * string

  let parser =
    let open Angstrom in
    let horizontal = function
      | ' ' | '\t' | '\r' -> true
      | _ -> false
    in
    let marker =
      skip_while horizontal
      *> char '@'
      *> lift2
           (fun name text -> Marker (name, String.strip text))
           (take_while1 (fun char -> Char.is_alpha char || Char.equal char '_'))
           (skip_while horizontal *> take_till (Char.equal '\n'))
    in
    let text = take_till (Char.equal '\n') >>| fun text -> Text text in
    many (peek_char_fail *> (marker <|> text) <* (char '\n' *> return () <|> end_of_input))
    <* end_of_input
  ;;
end

let identifier value =
  (not (String.is_empty value))
  && (Char.is_alpha value.[0] || Char.equal value.[0] '_')
  && String.for_all value ~f:(fun char -> Char.is_alphanum char || Char.equal char '_')
;;

let read (annot : 'a def_annot) =
  let%map.Option comment = annot.doc_comment in
  let fail line message =
    raise (Reporting.err_general annot.loc [%string "doc comment line %{line#Int}: %{message}"])
  in
  let lines =
    match Angstrom.parse_string ~consume:All Line.parser comment.contents with
    | Ok lines -> lines
    | Error message -> fail 1 [%string "invalid doc comment: %{message}"]
  in
  let blocks =
    List.foldi lines ~init:[] ~f:(fun index blocks line ->
      match line, blocks with
      | Line.Marker (name, text), _ -> (Some name, index + 1, [ text ]) :: blocks
      | Text text, _ when String.is_prefix (String.strip text) ~prefix:"@" ->
        fail (index + 1) "malformed doc marker"
      | Text text, (name, line, contents) :: rest -> (name, line, text :: contents) :: rest
      | Text text, [] -> [ None, index + 1, [ text ] ])
    |> List.rev_map ~f:(fun (name, line, contents) -> name, line, List.rev contents)
  in
  let empty =
    { body = ""
    ; brief = None
    ; parameters = []
    ; notes = []
    ; related = []
    ; notation = None
    ; id = None
    ; anchors = []
    }
  in
  let text contents = String.concat ~sep:"\n" contents |> String.strip in
  let append left right = String.concat ~sep:"\n\n" [ left; right ] |> String.strip in
  let entry line contents =
    match contents with
    | first :: rest ->
      let name, tail =
        let open Angstrom in
        let parser =
          lift2
            (fun name tail -> name, tail)
            (take_while1 (fun char -> not (Char.is_whitespace char)))
            (skip_while Char.is_whitespace *> take_while (fun _ -> true))
        in
        match parse_string ~consume:All parser (String.strip first) with
        | Ok pair -> pair
        | Error _ -> "", ""
      in
      let description = text (tail :: rest) in
      if (not (identifier name)) || String.is_empty description
      then fail line "@param and @anchor need a name and nonempty text";
      ({ name; text = description } : Entry.t)
    | [] -> fail line "missing marker payload"
  in
  List.fold blocks ~init:empty ~f:(fun doc (name, line, contents) ->
    let value = text contents in
    let singleton previous name =
      if Option.is_some previous then fail line [%string "duplicate @%{name}"];
      if String.is_empty value then fail line [%string "@%{name} needs nonempty text"];
      Some value
    in
    match name with
    | None -> { doc with body = append doc.body value }
    | Some "brief" ->
      let heading, body =
        List.split_while contents ~f:(fun line -> not (String.is_empty (String.strip line)))
      in
      let brief =
        List.map heading ~f:(fun line -> String.strip line)
        |> String.concat ~sep:" "
        |> String.strip
      in
      if Option.is_some doc.brief then fail line "duplicate @brief";
      if String.is_empty brief then fail line "@brief needs a title";
      { doc with brief = Some brief; body = append doc.body (text body) }
    | Some "param" ->
      let parameter = entry line contents in
      if List.exists doc.parameters ~f:(fun existing -> String.equal existing.name parameter.name)
      then fail line [%string "duplicate @param %{parameter.name}"];
      { doc with parameters = doc.parameters @ [ parameter ] }
    | Some (("note" | "usage" | "assumption") as tag) ->
      if String.is_empty value then fail line [%string "@%{tag} needs nonempty text"];
      let category = if String.equal tag "note" then "architecture" else tag in
      { doc with notes = doc.notes @ [ ({ category; text = value } : Note.t) ] }
    | Some "see" ->
      let names =
        String.split_on_chars value ~on:[ ','; ' '; '\n'; '\t'; '\r' ]
        |> List.filter ~f:(fun name -> not (String.is_empty name))
      in
      if List.is_empty names || not (List.for_all names ~f:identifier)
      then fail line "@see needs instruction names separated by commas or whitespace";
      { doc with related = doc.related @ names }
    | Some "notation" -> { doc with notation = singleton doc.notation "notation" }
    | Some "id" ->
      let id = singleton doc.id "id" in
      if not (String.for_all value ~f:(fun char -> Char.is_alphanum char || String.mem "_.-" char))
      then fail line "@id accepts letters, digits, dots, underscores and hyphens";
      { doc with id }
    | Some "anchor" ->
      let anchor = entry line contents in
      if List.exists doc.anchors ~f:(fun existing -> String.equal existing.name anchor.name)
      then fail line [%string "duplicate @anchor %{anchor.name}"];
      { doc with anchors = doc.anchors @ [ anchor ] }
    | Some name -> fail line [%string "unknown doc marker @%{name}"])
;;

let body annot = Option.value_map (read annot) ~default:"" ~f:(fun doc -> doc.body)
