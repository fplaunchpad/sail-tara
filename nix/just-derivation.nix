# Builds with the justfile's recipes, so every build command lives in one place.
# `fileset` lists the sources beyond the justfile itself; `recipes` build,
# `checkRecipes` run in the check phase.
{
  lib,
  stdenv,
  just,
}:

{
  fileset,
  recipes,
  checkRecipes ? [ ],
  nativeBuildInputs ? [ ],
  ...
}@args:

stdenv.mkDerivation (
  removeAttrs args [
    "fileset"
    "recipes"
    "checkRecipes"
  ]
  // {
    version = args.version or "0.6.0";
    src = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions (
        [
          ../justfile
          ../just
          ../sail_config.json
        ]
        ++ fileset
      );
    };
    nativeBuildInputs = [ just ] ++ nativeBuildInputs;
    env = {
      DUNE_CACHE = "disabled";
    }
    // args.env or { };

    preBuild = ''
      export HOME="$TMPDIR"
    '';
    buildPhase = ''
      runHook preBuild
      just ${lib.escapeShellArgs recipes}
      runHook postBuild
    '';

    doCheck = checkRecipes != [ ];
    checkPhase = ''
      runHook preCheck
      just ${lib.escapeShellArgs checkRecipes}
      runHook postCheck
    '';
  }
)
