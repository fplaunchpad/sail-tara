# The Lean support library the Sail Lean backend builds against (Lean 4.29.0).
{ fetchFromGitHub }:

fetchFromGitHub {
  owner = "rems-project";
  repo = "lean-sail";
  tag = "v6";
  hash = "sha256-Ba4tALZd6OHDj9cT2yTTOrNlHqJ2Rsj/9gUaLM0owMU=";
}
