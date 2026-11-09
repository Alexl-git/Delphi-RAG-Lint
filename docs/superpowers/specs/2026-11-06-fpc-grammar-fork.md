# E-FPC-LAZARUS: Free Pascal support, grammar fork first

Status: DESIGN, NOT-FOR-MERGE (lane x1, wave 146). Nothing here is merged or deployed.
Owner ruling 2026-10-27: (1) a grammar fork named like `tree-sitter-delphi-fpc`, from our
Isopod-based `tree-sitter-delphi13`, where `const fpc = false`; (2) later, maybe, an exe
switch, Delphi by default and FPC opt-in, that turns off Delphi-only rules and needs an FPC
platform library DB; (3) nothing beyond that: no Lazarus IDE plugin, no `.lpi`/`.lpk` project
model planned.

## What the measurement says

Sample found on this machine, no download: `{$mode objfpc}` units, `.pp` and `.lpr` files
(class `objfpc`, 153 files, 2.4 MB) and `{$mode delphi}` units (class `delphimode`, 54 files,
4.2 MB), deduplicated by content, `_OLD`/`_Stashed`/worktree copies excluded. Roots:
jcf-pascal-format\lazutils, graphics32, uib, Indy, SysTools, columbusegg4delphi, DelphiAST.
**There is no FPC RTL, compiler or LCL source on this machine** (no `fpcsrc`, no `rtl\`; the scan
covered C:\Projects, C:\dl, Downloads, E:\DOWNLOADS, E:\WORK, P:\DOWNLOADS, D:\Programs). The
sample is portable FPC-flavoured code; RTL-only idioms are covered by the probes below only.
Assumption the owner can reverse: an FPC source tarball was not downloaded (lane brief).

Files with no ERROR or MISSING node, measured with the v0.24.7 CLI over a private config and lib dir:

| set | current grammar (master 94fedd5) | fork branch (7fc97b1) |
|---|---|---|
| `objfpc`, raw | 146 of 153 | 148 of 153 |
| `delphimode`, raw | 48 of 54 | 49 of 54 |
| `objfpc`, preprocessed | 149 of 153 | 150 of 153 |
| `delphimode`, preprocessed | 54 of 54 | 54 of 54 |
| FPC construct probes | 36 of 80 | 81 of 85 (the 80 plus 5 added later) |
| Delphi sample (spring4d, RTL common, VCL, OTL) | 518 of 533 | 518 of 533, same files |

"Preprocessed" means `preprocessor\preprocess.js` with an FPC define set this lane wrote (`FPC`,
`FPC_OBJFPC`, `VER3_2`, `FPC_FULLVERSION=30202`, `MSWINDOWS`, `WIN64`, `LCL`...), includes
expanded. A count is files, not errors: the CLI reports one error per file.

**Read the sample numbers with care: they do not show that the current grammar handles FPC.** The
sample barely exercises the dialect. Of the 153 `objfpc` files, 0 use `specialize`, 2 use
`generic`, 1 uses `is nested`, 1 a top-level `operator`, 1 a bracket modifier, 0 `bitpacked`. It is
portable code that also compiles under FPC. The **probes** are the dialect measure, and on them the
current grammar fails 44 of 80. The probes were written from memory of the FPC reference and no FPC
compiler is on this machine, so a probe can be wrong about FPC; two came from the sample.

Remaining failures on the fork, preprocessed `objfpc` set:
* `paswstring.pas`: `procedure p; [external name 'X'];` with no body in the implementation section. A
  real gap, kept as a known-gap probe.
* `LowLevelTest.lpr` (graphics32): an unterminated string in its `uses` list. The source is broken.
* `WebServer.pas` (superobject demo): `(ctx.S['x'] := 'index');`, an assignment in parentheses. Not
  analysed further; it is not an FPC construct this lane knows of.

The raw-only failures (`SynRegExpr`, `RegExpr`, `laz2_xmlread`, ...) disappear once the preprocessor
picks one branch, so they are the existing `{$IFDEF}` limit and not dialect gaps.

Tree parity on Delphi code: 487 of 488 files under 120 KB give a byte-identical tree, positions
included. The one difference is error recovery inside `System.Win.OleControls.pas`, which fails on
both parsers (47 error lines on master, 46 on the fork). This comparison found a real regression
earlier: enabling `operatorName` turned Delphi's `class operator In` from an `identifier` into a
`kIn` node, with no change in pass/fail. It is fixed and has a probe. Files over 120 KB were not compared.

Cost of the fork against master: `parser.c` 18.06 MB to 23.04 MB, states 11428 to 13294, DLL 3.34 MB to
4.56 MB, `tree-sitter generate` about 28 minutes on the shared machine. Parse speed was not compared,
because the machine was too loaded for that to mean anything.

What the fork accepts now, all behind `enable_if(fpc, ...)`: `generic` and `specialize` in type,
ancestor, parameter, expression and call position; symbol operators with a named result (`operator +
(a, b: T) r: T`, `:=`, `**`, `><`, comparisons); `**` and `><` expressions; bracket modifiers (`[public,
alias: 'x']`, `[external name 'X']`, `[internproc: x]`, `[internconst: x]`); `public` and `public name`
at unit scope; `var x: T; public|export name 'y';`; the FPC calling-convention and modifier words;
`is nested`; `bitpacked`; `otherwise`; `(a := 1)` enum values; numeric labels; `asm ... end ['eax']`;
`program p(input, output);`.

Known gaps, all recorded in `test\fpc-probes\KNOWN-GAPS.txt`: Objective-Pascal (`objcclass`,
`objcprotocol`, `objccategory`), `cppclass`, and the body-less bracket form in an implementation
section.

Guard: `tools\fpc-probe-run.ps1` in the fork. Green on 87 probes (6 expected failures: 5 known gaps
plus the positive control `ctrl_broken`). Red when a known gap is dropped from the list; checked.

## Options

**A. Hard fork: a separate repo `tree-sitter-delphi-fpc` (the ruling).** Own `grammar.js`, own
generated parser, own DLL, exported symbol `tree_sitter_delphi_fpc`. Delphi parser bytes do not
change, so no Delphi re-parse and no extractor fingerprint risk. Cost: every grammar fix on
`tree-sitter-delphi13` has to be merged across.

**B. One `grammar.js`, two generated parsers (env var at generate time).** No merge cost at all,
but every FPC edit sits in the file that the Delphi release is cut from, and a mistake in an
`enable_if` changes Delphi parser bytes, which means a re-parse of every DB.

**C. Superset: accept FPC syntax in the Delphi parser.** One DLL, no switch. Rejected: it changes
Delphi parsing (`otherwise`, `public name`, `[..]` after a routine compete with real Delphi code
and RTTI attributes), the parser grows, and every DB re-parses for a dialect most users never
write. The measurements above show the flag costs parser size and generate time too.

**Chosen: A, with one discipline taken from B.** Every FPC-only rule stays behind
`enable_if(fpc, ...)` and the fork's diff against `grammar.js` stays small, so `git merge` from
`tree-sitter-delphi13` stays cheap, and folding back into B stays possible if the merge cost turns
out to bite. The owner can reverse this by asking for B; the branch converts by replacing the two
constants with an env read.

## Phases

1. **Grammar branch (this lane).** `lane/146-x1-fpc` on a worktree of
   `C:\Projects\tree-sitter-delphi13`, at `...\146\x1\grammar`. Flag on, renamed grammar
   (`delphi_fpc`), new rules behind the flag, probes as corpus tests, measured against the sample,
   Delphi no-regress check on a Delphi sample. Not merged, not pushed.
2. **Repo.** On the owner's go: create `tree-sitter-delphi-fpc`, carry the branch over, rename the
   bindings (`binding.gyp`, `bindings\`, `package.json`, wasm target), attribution to Isopod and
   Philip Zander as in the parent. Then get a real FPC sample (owner decides on the download:
   `fpcsrc` RTL + compiler, LCL) and drive the failures down.
3. **Maybe: the exe switch (the ruling's "later, maybe").** Separate design when asked. What this
   lane found it would touch, from the index:
   - `tree_sitter_delphi13` is imported in three units (`DRagLint.Parser.Delphi13`,
     `DRagLint.Diagnostics.AstChecks`, `DRagLint.Diagnostics.ParseCache`), each binding the DLL
     statically; a switch needs a runtime-selected language, and one DB must hold one dialect.
   - `DRagLint.Preprocess.Profile.PlatformBuiltins` hard-codes the Delphi define sets (`ver370`,
     `dcc`, ...). FPC needs its own (`fpc`, `ver3_2`, `objfpc`, `fpc_fullversion`, ...), plus
     `{$mode}` and `{$modeswitch}` handling and `{$define x:=y}` macros.
   - The `.dpr` literal lists in `DRagLint.CLI*` decide what a project file is; `.pp`, `.lpr` are
     not on them, and an `.lpi` is not a project by the ruling. So indexing is directory-scoped.
   - Node kinds stay Delphi's where the syntax is shared (`bitpacked` is aliased to `kPacked`),
     so the extractor keeps working. New kinds (`kSpecialize`, `kNested`) are ignored until taught.
   - Rules: a Delphi-only list has to be turned off; not surveyed here.
   - An FPC platform library DB needs FPC source (see above).

Out of scope by ruling: Lazarus IDE plugin, `.lpi`/`.lpk` project model.

## Assumptions the owner can reverse

* Branch from `master` (94fedd5, v1.4.2), not from any in-flight grammar lane (lane b2 holds
  `lane/146-b2` on the same repo at the same time).
* Only the objfpc/delphi language modes are targets; `{$mode macpas}`, `{$mode iso}` and
  `{$mode tp}` are not.
* Objective-Pascal (`objcclass`...) and `cppclass`: not in the first batch; see the table.
* The fork's DLL, when it exists, is not stamped by the engine's version guards until phase 3.
