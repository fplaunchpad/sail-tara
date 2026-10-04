# Sail Lem register-name reproduction

This reproduces a Sail 0.20.3 Lem backend bug with the register `MEM`. Sail emits a valid escaped record field (`MEM'`) but unescaped accesses (`s.MEM`), so Lem rejects the generated file. The same input succeeds after applying the proposed fix.

From the repository root, run:

```sh
nix-build upstream/sail-lem-register-keywords/default.nix --no-out-link
```

The expression pins the nixpkgs revision and Sail 0.20.3 source archive. It builds unpatched and patched Sail, generates Lem for `model.sail`, verifies that Lem rejects the first result, then typechecks the patched result with Sail's Lem library. It needs no TARA flake package or lockfile changes. `fix.patch` links to the retained canonical patch at `nix/patches/sail-lem-register-keywords.patch`.

The output path printed by `nix-build` contains the generated files and logs in `before/` and `after/`.

The standalone archive contains the patch itself. After unpacking, run `nix-build default.nix --no-out-link` inside its directory. `issue.md` is a draft for an upstream report.
