# LaTeX for the typeset specification. Sail's listing style needs xcolor, fullpage (preprint),
# listings and hyperref; doc/tara.tex adds etoolbox, geometry and fancyhdr for the page, lm for
# the fonts, and booktabs and tools (array) for the tables.
{ texliveBasic }:

texliveBasic.withPackages (
  ps: with ps; [
    latexmk
    listings
    xcolor
    preprint
    hyperref
    etoolbox
    geometry
    fancyhdr
    lm
    booktabs
    tools
  ]
)
