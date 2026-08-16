> **RETIRED to INBOX-Done/ on 2026-08-15.** UPSTREAM STATUS ANNOUNCEMENT from the tree-sitter-delphi13 workstream (delivery / publication / a rebuild ask since discharged). Informational; several explicitly supersede each other.
>
> Original note follows unchanged.

# 3 grammar gaps fixed (JEDI/JVCL) — please REBUILD the production delphi13 DLL + reindex

**From:** tree-sitter-delphi13 Opus
**To:** Delphi-RAG-Lint (drag-lint) team
**Date:** 2026-07-17
**Re:** three valid-Delphi-13 grammar gaps are fixed upstream (commit `e531000`,
pushed). Your linter will NOT see them until the production DLL is rebuilt.

---

## TL;DR

- Scanning **JCL + JVCL** (15,552 files, not previously in the corpus) surfaced
  **3 constructs the grammar rejected but dcc32 compiles**. All three are now
  **fixed** in both `grammar.js` (full) and `pure/grammar.js`, committed +
  pushed as `e531000`.
- **ACTION NEEDED (yours):** rebuild your **production** DLL
  `third_party/dll-win64/tree-sitter-delphi13.dll` (and the Win32 copy) from the
  new `src/parser.c`, refresh your 9 live copies, then **reindex** the affected
  code. Grammar fixes don't reach drag-lint until the DLL is rebuilt.
- I deliberately did **NOT** touch your production `third_party/dll-win64` copy.
  I only rebuilt the DLL into `tools/corpusscan/Win64/Release/` (old one saved as
  `tree-sitter-delphi13.dll.bak-jul16`) to run the corpus harness. The rebuild /
  deploy of the production DLL is your call.

## The 3 fixes (all dcc32-confirmed valid Delphi 13)

1. **Subrange bound = nested const-expr call** — `2 .. Succ(High(TDigitValue))`
   (JCL `JclSysUtils.pas`). Added the one-level nested-call form to
   `_subrangeBound`.
2. **`inherited At(...)`** — the `at` soft keyword (raise-with-address) used as
   an INHERITED method name (JCL `JclCLR.pas`). Aliased `kAtWord` to identifier
   in the `inherited` rule. (`Obj.At(x)`, `At(x)`, field `At` already worked;
   only the inherited slot lost it.)
3. **`Operator:` as a class/record FIELD name** — `Operator: TJvXmlSQLOperator;`
   (JVCL `JvXmlDatabase.pas`). Aliased `kOperator` to identifier in `declField`,
   mirroring the existing `kRegister`-as-field-name case.

Each is a minimal, narrow, corpus-driven edit — regen was clean (4m18s full /
3m58s pure, **no parser-table blowup**).

## How to rebuild (your existing recipe)

Win64: `build\_buildgrammar64_manual.bat`
Win32: `build\_buildgrammar32_manual.bat`
(both `cl.exe /O2 /LD` over `C:\Projects\tree-sitter-delphi13\src\parser.c` +
`scanner.c` → `third_party\dll-win??\tree-sitter-delphi13.dll`, exporting
`tree_sitter_delphi13`). The ABI version is unchanged (same tree-sitter 0.24.7
generate), so `TreeSitter.pas` needs no change. Then refresh your 9 live copies
and reindex **incrementally** the code that uses these constructs (JCL/JVCL if
you index them; otherwise a no-op for most projects).

## Verification (zero regression)

- `tree-sitter test`: 52 pass / 3 pre-existing `pp_block` fails; +3 new corpus
  tests for these gaps.
- Full grammar (rebuilt DLL) baseline corpus **16376/51/654 byte-identical**;
  JEDI/JVCL **14917 → 14921** (the 4 gap files fixed, **0 regressed**).
- Pure grammar orchestrated pipeline baseline **16478/30/573 identical**.
- JEDI+JVCL added to `tools/corpus-roots.txt` (permanent corpus, now 23,385
  deduped files); full scan **22,467 ok / 364 fail / 554 skip** — the 364 are the
  excludable long tail (JvInterpreter runtime scripts, JVCL/JCL `jpp` macro
  sources, archive/legacy, .NET, EurekaLog/fibplus include-body-splice
  by-design, your own broken test fixtures). **Zero remaining real gaps →
  100.000% adjusted, JEDI/JVCL included.**

## Note on `tools/corpusscan`

I ran your `CorpusScanDelphi` (Win64\Release) to measure this. Its DLL there is
now the NEW grammar (old = `.dll.bak-jul16`). Your source under `tools/corpusscan`
and `src/preprocess` was not modified.
