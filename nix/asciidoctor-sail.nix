# The pinned Asciidoctor HTML/PDF toolchain with Sail's documentation plugin.
{ lib, bundlerApp }:

bundlerApp {
  pname = "asciidoctor-sail";
  gemdir = ./asciidoctor;
  exes = [
    "asciidoctor"
    "asciidoctor-pdf"
  ];
  meta = {
    description = "Asciidoctor HTML and PDF converters with the Sail plugin";
    homepage = "https://github.com/Alasdair/asciidoctor-sail";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
