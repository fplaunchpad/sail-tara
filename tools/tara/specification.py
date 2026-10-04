"""Write the specification of TARA, in LaTeX and in AsciiDoc, from the Sail model.

    sail --doc --doc-embed plain --doc-embed-with-location --doc-bundle tara.json -o DIR model/syntax.sail
    sail --latex --latex-prefix tara model/syntax.sail
    python -m tara.specification --bundle DIR/tara.json --commands sail_latex/commands.tex \\
        --latex specification.tex --asciidoc tara.adoc

`tara.document` reads the model's documentation bundle into a specification; `tara.latex` and
`tara.asciidoc` write it.
"""

from pathlib import Path

import click

from tara.asciidoc import render_asciidoc
from tara.document import build
from tara.latex import render_latex
from tara.sail_doc import Macros, parse_bundle

FILE = click.Path(dir_okay=False, path_type=Path)
EXISTING_FILE = click.Path(exists=True, dir_okay=False, path_type=Path)


@click.command()
@click.option(
    "--bundle",
    type=EXISTING_FILE,
    required=True,
    help="The documentation bundle of the model, from sail --doc.",
)
@click.option(
    "--commands",
    type=EXISTING_FILE,
    help="The macros of the model, from sail --latex: sail_latex/commands.tex. Needed by --latex.",
)
@click.option(
    "--prefix",
    default="tara",
    show_default=True,
    help="The prefix of the macros: sail --latex-prefix.",
)
@click.option(
    "--latex", type=FILE, help="Write the sections of the document in LaTeX to this file."
)
@click.option("--asciidoc", type=FILE, help="Write the document in AsciiDoc to this file.")
def main(
    bundle: Path, commands: Path | None, prefix: str, latex: Path | None, asciidoc: Path | None
) -> None:
    """Write the specification of TARA, built from the documentation of the Sail model."""

    specification = build(parse_bundle(bundle))
    if latex is not None:
        if commands is None:
            raise click.UsageError("--latex needs --commands")

        macros = Macros.parse(commands, prefix=prefix)
        latex.write_text(render_latex(specification, macros), encoding="utf-8")

    if asciidoc is not None:
        asciidoc.write_text(render_asciidoc(specification), encoding="utf-8")


if __name__ == "__main__":
    main(prog_name="tara-specification")
