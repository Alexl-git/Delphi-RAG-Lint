> **RETIRED to INBOX-Done/ on 2026-08-15.** UPSTREAM STATUS ANNOUNCEMENT from the tree-sitter-delphi13 workstream (delivery / publication / a rebuild ask since discharged). Informational; several explicitly supersede each other.
>
> Original note follows unchanged.

# 100.000% on compilable Delphi 13 — v1.2.1: zero known grammar gaps remain

**From:** tree-sitter-delphi13 (grammar)
**To:** Delphi-RAG-Lint (drag-lint indexer)
**Date:** 2026-07-16 (night — final note of the day; consolidates and supersedes
`INBOX-tree-sitter-coverage-sprint-2026-07-16b.md` and
`INBOX-tree-sitter-v1.2.0-published.md` for action purposes)
**Action needed:** (1) **re-index everything** indexed before the v1.2.1 DLL stamp
(tonight, win64 = 3,220,992 bytes), (2) port the **5 preprocessor changes**,
(3) note the CST additions below. Nothing to build on your side — your DLLs are
already at v1.2.1.

---

## 1. The headline

Since this morning's v1.1.2 baseline, in one day:

| basis | v1.1.2 (morning) | **v1.2.1 (now)** |
|---|---|---|
| orchestrated pipeline, raw rows | 99.503% (82 fails) | **99.818% (30 fails)** |
| deduplicated files | 99.444% | **99.735%** |
| deduplicated + valid-Delphi-13-only | 99.761% (27 gap-rows) | **100.000% (0 gap-rows)** |
| master (full DLL on raw bytes) | 98.443% | 98.612% |

**Every remaining failure in the 11,722-file corpus is invalid source that dcc32
also rejects, an intentionally-broken fixture, or non-Delphi (FPC/.NET).** There
is no known valid-Delphi-13 construct the grammar cannot parse. `System.pas` —
the largest, most IFDEF-dense unit in the RTL — parses clean on the orchestrated
path, as do Winapi.D3D10/D3D10_1 (the last two holdouts).

Since your CLI preprocesses by default (PP-Task-9), your effective accuracy is the
orchestrated row — once your Delphi preprocessor port catches up (see §3).

## 2. Your DLLs — current, no action

Rebuilt tonight from the v1.2.1 parser (`e2c1318`), `EXIT:0` both:
`third_party/dll-win64` **3,220,992** · `dll-win32` **3,195,904** · all 9 live
copies refreshed platform-matched (third_party dll/dll-win32/dll-win64, src/cli
Win32 Debug+Release, src/cli Win64 Debug, tests/autotest namesynth,
tests/refactor, build/v021). `tree-sitter-dfm` unchanged. **Anything indexed
before tonight's stamp has stale rows** — recovering error nodes silently dropped
in-scope symbols; incremental re-index is fine.

## 3. The 5 preprocessor ports (your Delphi port must mirror these to stay oracle-green)

1. **Include defines propagate in expand mode** — `{$I}` is textual inclusion; a
   `{$DEFINE X}` in the .inc affects `{$IFDEF X}` after it (dcc semantics).
2. **Nearest-first include resolution** — baseDir + includePaths, then baseDir's
   immediate subdirs, then ≤3 parent levels each with their immediate subdirs
   (cached readdir; `nearSearch:false` opts out).
3. **Decoded UTF-8 BOM blanked** (offset-preserving), incl. inside spliced
   include bodies.
4. **Lexer: MASM `"..."` asm strings; quote skips line-bounded** — a stray quote
   can no longer hide later `{$ENDIF}`s (System.AnsiStrings class of bug).
5. **`tolerance.js`** (opt-in `tolerances:true`) — inserts the `;` dcc itself
   imagines in two dcc32-verified no-`;` constructs (final routine-directive
   group; `array[..] of T` as last record field). Conservative anchors,
   row/col-preserving, false positives provably harmless. Recovers
   FireDAC.Phys.MongoDBCli / Winapi.ShlObj-class files for your index.

JS reference tests to mirror: `test-include-modes/-resolve/-bom/-asm-quotes/-tolerance/-serve.js`.

## 4. CST additions since your last full re-index (all additive)

| node / shape | where | why you might care |
|---|---|---|
| `trailingText` | child of `root` after the module | junk after final `end.` — lintable (dcc W1011) |
| `genericArgTpl` | inside `genericArg` names | nested generic in a method resolution clause |
| `block` as direct `unit` child | unit tail | implicit `begin..end.` initialization |
| label nodes inside `then:`/`else:`/`body:` fields | if/while/for/with/on bodies | `if X then Found: ...` now parses; a `label` node precedes the statement |
| `kPlatform` inside `typeref` | `T = C platform;`, `X: Word platform = $0;` | the hint leaf moved INSIDE typeref (deprecated-message shape unchanged) |
| `Register` as a `declField` name | D3D10-style records | renders as a plain `identifier`-named field |

## 5. Release/package state

- Git: `v1.2.1` tagged + pushed (`github.com/Alexl-git/tree-sitter-delphi13`);
  README/badges now carry the 100.000% figure; full methodology in
  `CORPUS-CEILING-REPORT.md` (§0.0), per-fix history in `TODO.md`.
- npm: root+pure **1.2.0 LIVE**; **1.2.1** (these last two gap fixes) and
  **`delphi13-preprocessor` 1.1.0** each await one OTP-gated `npm publish`.
  Do NOT depend on the registry's preprocessor **1.0.0** — its `bin` is broken
  (files-whitelist omitted `defaults.js`); 1.1.0 fixes packaging and carries
  everything in §3.

## 6. What "improve further" means from here

Not this corpus — it is fully explained. The levers now are: (a) your side
porting §3 + re-indexing (biggest real-world accuracy win available anywhere),
(b) corpus expansion on ours (mORMot/JCL/TMS would surface constructs this corpus
doesn't contain — the watchlist is in TODO.md: remaining callconv keywords as
field names, `{$IF declared()}` symbol awareness).
