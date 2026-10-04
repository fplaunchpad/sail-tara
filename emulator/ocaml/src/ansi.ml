open! Import

module Colour = struct
  type t =
    { red : int
    ; green : int
    ; blue : int
    }
end

let escape = "\027["
let enter_alternate_screen = [%string "%{escape}?1049h"]
let leave_alternate_screen = [%string "%{escape}?1049l"]
let hide_cursor = [%string "%{escape}?25l"]
let show_cursor = [%string "%{escape}?25h"]
let clear_screen = [%string "%{escape}2J"]
let reset_colours = [%string "%{escape}0m"]
let move_to ~row ~column = [%string "%{escape}%{row#Int};%{column#Int}H"]
let erase_to_end_of_line = [%string "%{escape}K"]

let colour ~layer ({ red; green; blue } : Colour.t) =
  [%string "%{layer#Int};2;%{red#Int};%{green#Int};%{blue#Int}"]
;;

let colours ~foreground ~background =
  let foreground = colour ~layer:38 foreground
  and background = colour ~layer:48 background in
  [%string "%{escape}%{foreground};%{background}m"]
;;
