open! Core

let now () =
  let gettime = Or_error.ok_exn Core_unix.Clock.gettime in
  gettime Monotonic |> Time_ns.of_int63_ns_since_epoch
;;
