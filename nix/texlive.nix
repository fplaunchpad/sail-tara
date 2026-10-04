# LaTeX for the typeset specification: Sail's listing style needs xcolor,
# fullpage (preprint), listings and hyperref.
{ texliveBasic }:

texliveBasic.withPackages (
  ps: with ps; [
    latexmk
    listings
    xcolor
    preprint
    hyperref
  ]
)
