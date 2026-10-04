# Rocq support library for Sail-generated definitions, using stdpp bitvectors.
{
  lib,
  mkRocqDerivation,
  stdpp,
}:

mkRocqDerivation {
  pname = "sail-stdpp";
  opam-name = "rocq-sail-stdpp";
  owner = "rems-project";
  repo = "coq-sail";
  version = "0.20.3";
  release."0.20.3" = {
    rev = "e7b914cddc032e3676eebd87a808229828013e9c";
    hash = "sha256-SEac4aAYl2jMHEGMXdi/VjjXB89nS8FVB/UizcEnUPM=";
  };
  useDune = true;
  propagatedBuildInputs = [ stdpp ];

  meta = {
    description = "Rocq support library for Sail-generated specifications (stdpp bitvectors)";
    license = lib.licenses.bsd2;
  };
}
