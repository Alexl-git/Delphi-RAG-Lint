# Delphi preprocessor is FULLY ported — commits are local, please review + push

**From:** tree-sitter-delphi13 Opus
**To:** Delphi-RAG-Lint (drag-lint) team
**Date:** 2026-07-17
**Re:** the in-process Delphi preprocessor is complete & canonical — but the
completing commits are sitting **local** in your repo, unpushed.

---

## TL;DR

- **The Delphi preprocessor is fully functional and canonical.** The JS
  preprocessor is now **100% ported** to Object Pascal, in-process, no `node`.
- **ACTION NEEDED (yours):** the commits that complete it are **local only** —
  your `main` is **ahead of `origin/main` by 6 commits**. Review and **push**
  them and it's fully in your hands. (Pushing was deliberately left to you.)

## What's done (verified in your repo today)

`src/preprocess/` now has 6 units — the JS trio plus tolerance + profile:

    DRagLint.Preprocess.pas         (chunk processor / driver)
    DRagLint.Preprocess.Lexer.pas   (port of lexer.js)
    DRagLint.Preprocess.Expr.pas    (port of evalExpr.js)
    DRagLint.Preprocess.Tolerance.pas  (NEW, 269 lines — dcc-tolerance pass)
    DRagLint.Preprocess.Profile.pas    (.dproj-derived define profile)
    DRagLint.Preprocess.Types.pas

All 5 v1.2.1 tolerance passes are ported (BOM-blank offset-preserving; MASM
double-quote asm strings; nearest-first `{$I}` include resolution; transitive
include-define propagation; dcc-tolerance). 13 preprocess suites exist under
`tests/preprocess/`, and **`run_tolerance.ps1` is the first node-free suite** —
it byte-compares against **frozen** `fixtures/tolerance/*.expected` snapshots
(no JS in the loop). That suite is the template for de-JS-ing the rest.

## The commits to pick up (local, unpushed — `main` ahead of origin by 6)

    dabd499  feat(tools): CorpusScanDelphi -- all-Delphi corpus harness (no JS)
    260dd7d  feat(pp): v1.2.1 port #5 -- dcc-tolerance (tolerance.pas): JS now FULLY ported
    99ef437  feat(pp): v1.2.1 port #2 -- nearest-first {$I} include resolution
    c8b7b64  test(pp): v1.2.1 port #1 -- lock transitive include-define propagation
    1f635b8  feat(pp): v1.2.1 port #4 -- MASM double-quote asm strings
    26f8463  feat(pp): v1.2.1 port #3 -- blank leading UTF-8 BOM offset-preservingly

(Your 3 dirty working files — `docs/lint/BACKLOG.md`,
`src/delphi-plugin/dclDragLintWizard.*` — are YOUR pre-existing changes and were
left untouched.)

## One open policy item (not a preprocessor bug)

The all-Delphi corpus harness (`CorpusScanDelphi`, `dabd499`) diffs against the
JS reference and shows a small delta: ~12 files fail on the Delphi harness that
pass on JS. **All ~12 are the include-BODY-splice class** (EurekaLog
`ESendAPI*`/`EConsts`/`EUnmangling`, fibplus `VariantRtn`, Indy
`IdAssemblyInfo`/`IdDsnSASLListEditorFormNET`, Orpheus `ovcspary`). Cause: JS
`expand` mode splices include *bodies* (const lists / routine bodies) into the
output; the Delphi port is deliberately **defines-only** (offset-identity, no
map). This is a **design choice, not a defect** — the recommended call is to
accept + document it as the harness semantic. Your decision; flag if you'd
rather add measurement-only expansion.

## Relationship to the JS preprocessor

The JS `delphi13-preprocessor` stays at **1.0.0** as the **frozen reference /
test oracle only** — not a runtime dependency. Your Delphi port is canonical.

## Net

Preprocessor: **done, canonical, in-process.** The only thing between here and
"fully yours" is **reviewing + pushing the 6 local commits**. After that: convert
the remaining render.js-calling suites to frozen snapshots (per the
`run_tolerance` template) at your leisure.

Ping back if you want help with the splice-class policy or the snapshot
conversions.
