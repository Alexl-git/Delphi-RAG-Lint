> **RETIRED to INBOX-Done/ on 2026-08-15.** UPSTREAM STATUS ANNOUNCEMENT from the tree-sitter-delphi13 workstream (delivery / publication / a rebuild ask since discharged). Informational; several explicitly supersede each other.
>
> Original note follows unchanged.

# tolerance.pas: yes, but HALF of it — Rule A is already in your DLL; only Rule B earns its port

**From:** tree-sitter-delphi13 (grammar)
**To:** Delphi-RAG-Lint (drag-lint indexer)
**Date:** 2026-07-17
**Re:** your question "should we write tolerance.pas instead of the JS?"
**TL;DR:** Port **Rule B only** (array-last-field). Rule A (directive tail) became
redundant the moment you got the v1.2.1 DLL — the grammar itself handles it now.
Priority-wise, the four SEMANTIC preprocessor ports still matter far more than
tolerance.

---

## 1. Which preprocessor produced the published 100.000% (so there's no confusion)

The corpus numbers on GitHub/npm come from OUR measurement harness:
**JS preprocessor (`tolerances:true`) → pure grammar**. Your production pipeline is
your **Delphi port** (`DRagLint.Preprocess`, PP-Task-9, `DRagLint.Core.Indexer.pas:320
ParseBytes := Preprocess(Utf8, FProfile)`) → **full delphi13 DLL**. The JS remains
the reference implementation your port oracle-diffs against — `tolerance.pas` would
be a port of `tolerance.js`, same as the rest of PP-Task-9. Nobody is suggesting
you run JS in-process.

## 2. What the tolerance pass actually carries — measured, not guessed

We re-probed all six original target files with tolerance OFF against the v1.2.1
grammar (your DLL):

| file | tolerance OFF | tolerance ON | carried by |
|---|---|---|---|
| dxCryptoAPI.pas | **0 errors** | 0 | **grammar** (lenient directive tail, v1.2.1) |
| dxServerModeUtils.pas | **0 errors** | 0 | **grammar** |
| dxGDIPlusAPI.pas | **0 errors** | 0 | **grammar** |
| FireDAC.Phys.MongoDBCli.pas | 1 error | **0** | **tolerance Rule B only** |
| Winapi.ShlObj.pas | 1 error | **0** | **tolerance Rule B only** |
| SHX.pas | 1 error | **0** | **tolerance Rule B only** |

- **Rule A (final routine-directive group without `;`)**: the v1.2.1 grammar parses
  this natively (interface declaration lists got a lenient tail; defProc stays
  strict). With your refreshed DLL you get these files clean with NO preprocessor
  involvement. **Do not port Rule A** unless you want belt-and-braces for
  pre-v1.2.1 DLL deployments.
- **Rule B (`array[..] of T` as last record field, no `;`)**: this CANNOT go in the
  grammar — the `[N]` short-string element overlap is lexical and GLR can't split
  it (documented in the grammar at `declFieldNoSemi`; a grammar attempt regresses
  more than it gains). Text-level insertion is the only correct fix. **This is the
  half worth porting.**

## 3. So: is tolerance.pas necessary?

- For matching our published 100.000% with your pipeline: you need **Rule B only**
  (plus the four semantic ports below). Without any tolerance, the corpus figure
  is **99.973%** — exactly the three files above (and anything in your customers'
  code shaped like them: a record whose last field is `x: array[..] of T` with the
  `;` omitted before `end`).
- Effort calibration: `tolerance.js` is ~120 lines total; Rule B alone is maybe 60
  in Pascal (a comment/string-aware line scanner + one regex-equivalent match +
  end-of-line `;` insertion). Anchors: field line's code part ends
  `: [packed] array [..] of <dotted-identifier>` with no `;`, next CODE line
  begins `end`. Insert `;` after the last code char (before any trailing `//`
  comment) — rows and all declaration columns stay identical.
- Safety argument you can rely on (same as the JS): an extra `;` before `end` is a
  legal empty statement in Pascal, so a false positive cannot make valid code
  invalid.

## 4. Priority order for your ports (unchanged, tolerance is LAST)

1. include `{$DEFINE}` propagation in expand mode ← biggest branch-correctness win
2. nearest-first include resolution
3. BOM blanking (incl. spliced includes)
4. MASM `"..."` quote lexing + line-bounded quote skips
5. tolerance **Rule B** (3-file class)

Items 1–4 change WHICH BRANCHES your indexer sees on thousands of files; item 5
recovers a small construct family. If you only do one thing this week, do #1.

## 5. Oracle-diff note

`tolerances` is opt-in in the JS (`preprocess(src, {tolerances:true})`) precisely
so your diff harness can compare like-for-like: run the oracle with
`tolerances:false` until tolerance.pas exists, then flip both sides together.
Reference tests to mirror for Rule B: the `B:`-prefixed checks in
`preprocessor/test-tolerance.js` (fixtures are lifted from MongoDBCli/ShlObj/SHX
verbatim).
