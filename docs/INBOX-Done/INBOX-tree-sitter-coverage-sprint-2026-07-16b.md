> **RETIRED to INBOX-Done/ on 2026-08-15.** UPSTREAM STATUS ANNOUNCEMENT from the tree-sitter-delphi13 workstream (delivery / publication / a rebuild ask since discharged). Informational; several explicitly supersede each other.
>
> Original note follows unchanged.

# Grammar + preprocessor coverage sprint — v1.2.0, DLLs refreshed, 3 new CST nodes, 5 preprocessor ports for you

**From:** tree-sitter-delphi13 (grammar)
**To:** Delphi-RAG-Lint (drag-lint indexer)
**Date:** 2026-07-16 (afternoon; UPDATED evening for v1.2.0 — read §0 first)
**Action needed:** (1) re-index anything indexed before **19:0x** (the v1.2.0 DLL
build — the 15:38 note below is superseded), (2) port **5** preprocessor changes,
(3) note 3 new CST node types.

---

## 0. EVENING UPDATE — v1.2.0 tagged+pushed; DLLs rebuilt AGAIN; one correction

- **Correction:** §2's "the master path (your path)" was stale — your PP-Task-9
  in-process preprocessing is **enabled by default in the CLI** (`--no-preprocess`
  opts out), so your effective pipeline is *your Delphi preprocessor → full
  delphi13 DLL*. Everything in this note still applies; the preprocessor ports
  below matter MORE, not less.
- **Three more fixes landed after the afternoon build**, so the DLLs were rebuilt
  a second time (win64 3,158,528 / win32 3,133,440, both EXIT:0, all 9 live copies
  refreshed platform-matched):
  - goto **label as a then/else/do body** (`if Index = 0 then Found: ...`,
    `while true do redo: case ...`) — recovers AsyncPro LFN, superobject;
  - **lenient directive tail in interface declaration lists** — the final
    directive group may omit its `;` (`function IsEq(...): Boolean; overload`),
    dcc32-verified; `defProc` headers stay strict, so a missing `;` before a body
    is still an error;
  - (grammar-side of things you already get via the full DLL.)
- **5th preprocessor port: the dcc-tolerance pass** (`tolerance.js`, opt-in
  `tolerances: true`) — inserts the `;` dcc itself imagines in two verified
  no-`;` constructs (final directive group; `array[..] of T` as last record
  field). Conservative anchors; row/col-preserving (only a same-line trailing
  comment shifts by one column); a false positive provably cannot make valid
  code invalid. With your default-on preprocessing this recovers
  FireDAC.Phys.MongoDBCli, Winapi.ShlObj and friends for your index too.
- Release: **v1.2.0** (root+pure) / **delphi13-preprocessor 1.1.0**, tagged and
  pushed. Corpus: orchestrated **99.770%** raw / **99.965%** on real Delphi 13
  (4 real-gap rows remain corpus-wide, all documented). npm publish pending auth.

---

## 1. TL;DR

Six commits landed today after the v1.1.2 morning refresh (`6f10463`…`9ce187b`, plus a
docs commit). Corpus effect, zero regressions at every step:

| path | before | after |
|---|---|---|
| orchestrated | 99.503% (82 fails) | **99.679% (53 fails)** |
| master (what YOU run) | 98.443% | **98.534%** |
| deduped + Delphi-13-only | 99.761% | **99.885% — gap 0.115%** |

Your `third_party` DLLs are already rebuilt from the committed parser
(**2026-07-16 15:38**, EXIT:0 both) and all **9 live copies** refreshed
platform-matched (third_party dll/dll-win32/dll-win64, src/cli Win32 Debug+Release,
src/cli Win64 Debug, tests/autotest namesynth, tests/refactor, build/v021). Frozen
release-artifacts bundles untouched, as before.

Sizes: win64 2,948,096 → **2,979,328**; win32 2,927,616 → **2,954,240**.

## 2. What the master path (your path) gained

- **Implicit `begin..end.` unit initialization** (Turbo-Pascal form, dcc-valid):
  bdemts, SHDocVw, System.Win.InternetExplorer, Winapi.OpenGL.PkgHelper now parse.
  If you index the RTL/BDE trees, these had whole-file ERROR before.
- **Text after final `end.`** (dcc W1011): tolerated, exposed as a `trailingText` node.
- **Nested generic in a method resolution clause**
  (`function TFunc<T1, IEnumerable<TResult>>.Invoke = Bind;`): new `genericArgTpl` node.
- **Control chars ≤ #31 between tokens are whitespace** (dcc behavior): recovers e.g.
  DevExpress dxPDFForm.pas, which ships a stray 0x12 byte.

## 3. Three NEW visible CST node types (additive — old queries unaffected)

| node | where | meaning |
|---|---|---|
| `trailingText` | direct child of `root`, after the module node | junk after the final `end.` — lintable (dcc W1011) |
| `genericArgTpl` | inside `genericArg` name slots | nested generic instantiation in a resolution clause |
| `block` | direct child of `unit` (new position; node type already existed for program/library) | implicit initialization block |

## 4. Preprocessor: FOUR changes to mirror in your Delphi port (oracle-diff will catch all of them)

Your port is canonical for you, but the JS oracle moved — these are correctness fixes
verified against dcc semantics:

1. **Include defines PROPAGATE in expand mode** (`preprocess.js`): `{$I}` is textual
   inclusion — a `{$DEFINE X}` inside the .inc affects `{$IFDEF X}` after it. The JS
   previously discarded child defines in expand mode (defines-only already shared).
2. **Nearest-first include resolution**: baseDir + includePaths, then baseDir's
   immediate subdirs, then up to 3 parent levels each with immediate subdirs (cached
   readdir; `nearSearch:false` opts out). Real layouts: EurekaLog `Source\Common\
   ELDefines.inc`, AsyncPro `PrnDrv\Win9xME\` → `source\AwDefine.inc`.
3. **Decoded UTF-8 BOM is blanked** (offset-preserving), including inside spliced
   include bodies (Velthuis `bases.inc` shipped a BOM mid-splice).
4. **Lexer: MASM `"..."` strings + line-bounded quote skips** — dcc's built-in
   assembler accepts `CMP AL,"'"`; the apostrophe inside `"..."` used to open a
   phantom string that swallowed later `{$ENDIF}`s (System.AnsiStrings was blanked
   from mid-file to EOF). Pascal strings can't span lines, so both quote skips now
   stop at end-of-line — a stray quote can no longer hide later directives.

New JS test files you can mirror: `test-include-resolve.js`, `test-bom.js`,
`test-asm-quotes.js` (plus updated expectations in `test-include-modes.js` /
`test-serve.js` — expand mode now takes the THEN branch in the shared fixture).

## 5. Why re-index

Same as the morning note: recovering error nodes drop in-scope symbols from your
index. Anything containing the constructs in §2 (RTL, BDE, DevExpress, AsyncPro
trees) indexed before **2026-07-16 15:38** has stale rows. Incremental is fine.

## 6. Status of the remaining known gaps (so you don't re-report them)

13 rows corpus-wide remain on the orchestrated path, all parked with recorded
reasons (see tree-sitter-delphi13 `TODO.md` session table): no-`;` final directive
group (3 DevExpress), labeled then/else-body (LFN ×2, superobject), System.pas ×2
(needs two fixes, one of which explodes generate — bisect-confirmed), `Register:`
field (D3D10 ×2), `array[..] of T` last-field-no-`;` (3). If your linting hits one
of these, it's known — no new report needed.

## 7. Not pushed / not published yet

The 7 commits are LOCAL on master (push pending). npm is still at 1.1.1/1.1.0
(publish blocked on `npm login`; v1.2.0-vs-v1.1.2 decision pending given the new
nodes). Your DLLs don't depend on either — they're built from the committed source.
