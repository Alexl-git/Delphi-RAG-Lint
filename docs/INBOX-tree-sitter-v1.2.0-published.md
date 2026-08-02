# v1.2.0 is LIVE on npm — your DLLs already match it; 5 preprocessor ports queued for you

> **v1.2.1 SAME-DAY UPDATE (read this first):** two more gaps closed —
> `Default8087CW: Word platform = $033F;` (System.pas ×6 sites; **System.pas now
> parses clean orchestrated**) and `Register: UINT;` as a record field name
> (Winapi.D3D10 ×2). **Adjusted corpus rate is now 100.000% on compilable
> Delphi 13** (orchestrated raw 99.818%; every residual failure is invalid
> source / fixture / FPC / .NET). Your DLLs were rebuilt AGAIN from v1.2.1
> (win64 3,220,992 / win32 3,195,904, EXIT:0, all 9 copies refreshed) — so
> re-index anything indexed before the v1.2.1 build stamp, not the v1.2.0 one.
> Two CST notes on top of §5: `T = C platform;` now carries `kPlatform` INSIDE
> `typeref` (the `deprecated 'msg'` shape is unchanged), and a field named
> `Register` renders as a normal `identifier`-named `declField`. Git tag
> `v1.2.1` is pushed; npm 1.2.1 (root+pure) + `delphi13-preprocessor` 1.1.0
> each await one OTP.

**From:** tree-sitter-delphi13 (grammar)
**To:** Delphi-RAG-Lint (drag-lint indexer)
**Date:** 2026-07-16 (evening)
**Re:** release notification — supersedes nothing; the coverage-sprint note
(`INBOX-tree-sitter-coverage-sprint-2026-07-16b.md`, incl. its §0 evening update)
remains the detailed changelog.
**Action needed:** (1) re-index anything indexed before today ~19:00, (2) port the
5 preprocessor changes, (3) nothing else — your DLLs are already current.

---

## 1. What shipped

- **`tree-sitter-delphi13` 1.2.0** and **`tree-sitter-delphi13-pure` 1.2.0** are
  published on npm (confirmed on the registry). `delphi13-preprocessor` **1.1.0**
  follows as soon as an OTP is entered (the 1.0.0 on the registry has a broken
  `bin` — its `files` whitelist omitted `defaults.js`; 1.1.0 fixes the packaging
  and adds everything below).
- Git: tag `v1.2.0` pushed to `github.com/Alexl-git/tree-sitter-delphi13`.
  Full changelog: `RELEASE-NOTES-v1.2.0.md` in the repo root.

## 2. Corpus numbers you can quote

| basis | v1.1.2 | v1.2.0 |
|---|---|---|
| orchestrated raw rows | 99.503% | **99.770%** |
| deduped + valid-Delphi-13-only | 99.761% | **99.965%** (4 known gaps corpus-wide) |
| master (full DLL on raw text) | 98.443% | 98.588% |

Since your CLI preprocesses by default (PP-Task-9), your effective accuracy tracks
the orchestrated row once your preprocessor port catches up.

## 3. Your DLLs — no action

`third_party/dll-win64` (3,158,528 bytes) and `dll-win32` (3,133,440) were rebuilt
from the exact v1.2.0 parser this evening, and all 9 live copies refreshed
platform-matched. `tree-sitter-dfm` unchanged.

## 4. The 5 preprocessor ports (oracle-diff will flag each until ported)

1. Include `{$DEFINE}`s propagate in **expand** mode (dcc textual-include semantics).
2. Nearest-first include resolution (baseDir subdirs → up to 3 parents each with
   their subdirs; `nearSearch:false` opts out).
3. Decoded UTF-8 BOM blanked, incl. inside spliced include bodies.
4. Lexer: MASM `"..."` asm strings; quote skips line-bounded.
5. **`tolerance.js`** (opt-in `tolerances:true`) — inserts the `;` dcc itself
   imagines (final directive group; `array[..] of T` last field). Conservative
   anchors, row/col-preserving, false positives provably harmless. With your
   default-on preprocessing this recovers FireDAC.Phys.MongoDBCli, Winapi.ShlObj
   etc. for your index.

JS reference tests: `test-include-modes/-resolve/-bom/-asm-quotes/-tolerance/-serve.js`.

## 5. Grammar changes that reach you through the DLL (already active)

Implicit `begin..end.` unit initialization · goto label as a then/else/do body ·
lenient directive tail in interface decl lists (defProc stays strict) ·
`trailingText` after final `end.` · `genericArgTpl` (nested generic in method
resolution clauses) · control chars ≤ #31 as whitespace. New CST node types are
additive: `trailingText`, `genericArgTpl`, `block` as a direct `unit` child.

## 6. Re-index reminder

Anything indexed before today ~19:00 predates the label/lenient-tail fixes (and
the afternoon batch). Incremental re-index is fine; error-recovery rows from older
DLLs silently dropped in-scope symbols.
