# Reference documentation

`tara.adoc` supplies the chapter layout. The build generates the instruction
sections and summary tables from the Sail plugin's typed metadata; native Sail
includes supply the prose and listings. Instruction groups follow their source
filenames and the matching `section_<group>` and `<group>` Sail comment anchors.
Missing group anchors fail the build.

The PDF and HTML share Petrona Regular for prose and JetBrains Mono for code.
Instruction names use inline code markup, so their section numbers and page
numbers keep the prose font.

To change the PDF fonts, edit `body_font_family`, `code_font_family`, and
`chapter_font_family` at the top of `tara-theme.yml`.
The remaining settings refer to those choices.
The `palette` block holds the PDF's text, accent, rule, and background colors.
Register a new family's regular, italic, bold, and bold italic faces under
`font.catalog`; filenames are relative to the packaged `fonts/` directory.

For HTML, change `--body-font`, `--code-font`, and `--chapter-font` in the
stylesheet's `:root` block, and register new local faces with `@font-face`.
Keep fallback families in the CSS choices for browsers that cannot load a font.
`nix/doc-fonts.nix` supplies the pinned, licensed font files for both formats.

Chapter number size and color belong to the PDF theme's `role.chapter-number`
and the stylesheet's `.chapter-number` rule.
`sections.rb` controls the section markers and aligned TOC number columns without
choosing fonts. The TOC uses ordinary serif text for its numbers and page labels.
Each dot aligns within entries whose components have the same digit counts.

`sail_config.json` sets the formatter width for build-only listing copies.
If the code font or PDF page geometry changes, adjust that width and inspect the
rendered listings. Run `just doc build` and `just doc html` to regenerate both
formats.
