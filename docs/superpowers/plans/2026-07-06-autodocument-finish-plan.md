# AutoDocument Finish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Track 2 (AutoDocument) end-to-end -- whole-unit/project batch, three new ground-truth doc-sources, two lint rules (`missing-doc`, `doc-drift`), and a DocInsight-collection spike -- including the deferred semantic-drift work reframed as a deterministic doc-vs-code diff.

**Architecture:** Two new reusable engines in `src/doc/` -- `TDocBatch` (drives the Chunk-1 single-decl orchestrator across N public declarations, one `TTextEdits` set through the existing `TTextEditApplier`/`FinalizeAndOutput` path) and `TDocDrift` (a pure deterministic analysis function diffing a `TParsedDoc` against the current signature + index facts). The three doc-sources extend the existing `TDocFactsBuilder`/`TDocRegions`; the two lint rules + `--fix` are thin consumers. Phased so structural pieces land first and `doc-drift` is the final bounded phase.

**Tech Stack:** Delphi 13 (RAD Studio 37), Object Pascal, tree-sitter (current full grammar DLL), SQLite/FireDAC, PowerShell test harnesses, `git` (opt-in for `<since>`), the delphi-build skill.

**Spec:** `docs/superpowers/specs/2026-07-06-autodocument-finish-design.md` (approved).

## Global Constraints

- **Encoding:** all `.pas` source + fixtures are strict 7-bit ASCII, CRLF, no BOM. Never Unicode/LF. DocInsight comments are `///` triple-slash on public surface (the project CDD rule). **Byte-verify every NEW `.pas` and `.ps1` is CRLF (0 lone-LF) before committing** -- dcc64 tolerates LF so the build won't catch it (a repeatedly-observed trap).
- **Build (authoritative gate):** run `build\build_draglint_win64.bat` via PowerShell `Start-Process cmd.exe -ArgumentList "/c","<bat>" -RedirectStandardOutput <log> -NoNewWindow -Wait -PassThru`; require ExitCode 0, no `[dcc64 Error]`/`E2xxx`/`Fatal`, and `OK: staged`. Do NOT use the MCP build tool; do NOT `cmd /c build.bat` from the Bash tool. **If the log says OK but the staged exe timestamp did not advance, orphaned `drag-lint.exe`/`drag_lint_graph.exe` hold a lock -- `taskkill /F /IM drag-lint.exe` + `taskkill /F /IM drag_lint_graph.exe`, then rebuild.**
- **New unit wiring:** every new `.pas` needs a `<DCCReference Include="..\doc\DRagLint.Doc.X.pas"/>` in `src/cli/drag-lint.dproj` (the `..\doc` search path already exists from Chunk 1) AND a `uses` entry where consumed.
- **Test the STAGED exe** `third_party\dll-win64\drag-lint.exe` from a NEUTRAL CWD (`C:\TEMP`), pwsh 7. Fixtures ASCII/CRLF, unit name = filename. Model harnesses on `tests/autodoc/run_*.ps1` (or `tests/callresolve/run_calls_resolved.ps1`): `[CmdletBinding()] param([string]$Exe=<staged exe>)`, a `Check($n,$ok)` helper, scratch dir under `C:\TEMP`, `Push-Location C:\TEMP` for a neutral CWD.
- **No fabrication:** batch is facts-only by default; a missing `<summary>` gets `TODO: describe.` ONLY under `--stubs`; `<since>` emits nothing rather than a guess when git is unavailable/decl moved; `doc-drift --fix` NEVER rewrites hand prose (only refreshes the managed block + adds missing param/returns stubs).
- **Idempotency:** a second `document` batch run and a second `doc-drift --fix` run must be BYTE-IDENTICAL (the Chunk-1 managed-region invariant, now at scale).
- **Guardrail (green after each task):** lint 154/154 (`tests\lint\run_lint_tests.ps1`), store 16/16, autodoc (existing 7 + new suites), autofix 9/9, callresolve 12/12, + the 9 preprocess harnesses. NOTE: Task 9 turns two new rules ON by default -- the lint count/fixtures may shift; INVESTIGATE each (correct new-rule finding vs regression), see Task 9.
- **Two rules ON by default** (user decision) with the noise mitigations: `missing-doc` is public/published-surface ONLY; both rules honor per-rule enable/severity config; first-run count is MEASURED + documented (Task 11).

**Key existing locations (verified 2026-07-06):**
- Single-decl orchestrator: `src/doc/DRagLint.Doc.Document.pas` -- `TDocumenter.BuildFor(store, qname): TDocumentResult` (`TDocumentResult = record Action: (daNotFound/daCreated/daExtended/daUnchanged); QName, FilePath: string; Line: Integer; Edits: TArray<TTextEdit>; end;`). Batch loops this.
- Facts: `src/doc/DRagLint.Doc.Facts.pas` -- `TDocFactsBuilder.Build(store, sym): TDocFacts` (`CalledFrom/Calls/UsedInUnits/Raises/ReturnType` + *Total). Doc-sources extend `TDocFacts` + `Build`.
- Regions: `src/doc/DRagLint.Doc.Regions.pas` -- `TDocRegions.RenderFactsBlock(facts, prefix)`, `MergeComment(existing, sigParams, facts, hasReturn, prefix)`, sentinels `AUTO_BEGIN/END/PARAM`. Doc-sources extend `RenderFactsBlock`.
- Parsed doc: `src/parser/DRagLint.Parser.DocComments.pas` -- `TDocCommentScanner.Scan`, `TParsedDoc` (`Summary, Remarks, ReturnsText, Params: TArray<TDocParam>{Name,Desc}, Exceptions, StartLine, EndLine, HasContent`). Drift diffs this.
- Signature backbone: `src/refactor/DRagLint.Refactor.DocStub.pas` -- `ExtractParamList`, `ParseParamNames`, `SignatureHasReturn`, `ReadSourceLine`.
- Apply substrate: `TTextEditApplier.Apply(edits, backup)` / `.RenderDryRun(edits)`; `FinalizeAndOutput(args, findings, defaultDisabled, emitText)` at `CLI.pas:4482`.
- CLI verb pattern: `DoDocument` at `CLI.pas:5553`; help lines ~`:322`; dispatch in the big `else if Args.Command = 'X'` chain (grep `Args.Command = 'document'`).
- Lint rule registry: `src/lint/DRagLint.Lint.RuleCatalog.pas` -- `TRuleCatalog.BuiltinRegistry: TArray<TRuleInfo>` (append new rules here). Project-level rule runner: `src/lint/DRagLint.Lint.ProjectRules.pas` -- `TProjectLintRules.Run(store, ruleId): TArray<TLintFinding>` (per-symbol iteration model for `missing-doc`/`doc-drift`).

---

## PHASE 1 -- Batch engine (structural core)

## Task 1: `TDocBatch` unit skeleton + facts-only whole-unit batch

**Files:**
- Create: `src/doc/DRagLint.Doc.Batch.pas`
- Modify: `src/cli/drag-lint.dproj` (DCCReference)
- Create: `tests/autodoc/run_document_unit.ps1`
- Create: `tests/autodoc/fixtures/docunit/twopublics.pas`

**Interfaces:**
- Consumes: `TDocumenter.BuildFor(store, qname): TDocumentResult` (Document.pas), `ISymbolStore`, `TTextEdit` (Model).
- Produces:
  ```pascal
  TDocBatchOptions = record
    Stubs         : Boolean;  // opt-in TODO summaries; default False = facts-only
    IncludeSeeAlso: Boolean;
    IncludeDeprecated: Boolean;
    IncludeSince  : Boolean;
    BaseDir       : string;   // repo root for git <since>; '' = cwd
  end;
  TDocBatchResult = record
    Edits    : TArray<TTextEdit>;
    DeclCount: Integer;  // public decls considered
    DocCount : Integer;  // decls that produced >=1 edit
  end;
  TDocBatch = class
    class function DocumentUnit(const AStore: ISymbolStore; const AUnitFile: string;
      const AOptions: TDocBatchOptions): TDocBatchResult;
  end;
  ```

- [ ] **Step 1: Write the failing test.**

`tests/autodoc/fixtures/docunit/twopublics.pas` (ASCII/CRLF, unit `twopublics`):
```pascal
unit twopublics;
interface
type
  TThing = class
  private
    FLast: Integer;
  public
    function Add(A, B: Integer): Integer;
    procedure Reset;
  end;
implementation
function TThing.Add(A, B: Integer): Integer;
begin Result := A + B; end;
procedure TThing.Reset;
begin FLast := Add(0, 0); end;   // Reset CALLS Add -> a real Calls fact -> managed block
end.
```
(`Reset` MUST call `Add` so it has a real outgoing-Calls fact -> a managed block
under the facts-only default; an empty `begin end;` Reset has no facts and would be
correctly SKIPPED, contradicting the "2 decls documented" assertion. `FLast` is a
private field, not a documented public decl.)
`tests/autodoc/run_document_unit.ps1` (model on `tests/autodoc/run_*.ps1`): index the fixture dir to a scratch DB, run `document --unit fixtures/docunit/twopublics.pas --apply` (facts-only default), then assert on the rewritten file:
- BOTH `TThing.Add` and `TThing.Reset` gained a `///` DocInsight comment (2 decls documented).
- `Add` has a managed facts block (`<!-- drag-lint:auto BEGIN -->`) and NO `TODO: describe.` (facts-only default -- no stub summary).
- `Reset` likewise (managed block, no TODO stub).
- IDEMPOTENCY: a second `document --unit ... --apply` leaves the file BYTE-IDENTICAL.
- The `--json` form reports `declCount` and `docCount`.

- [ ] **Step 2: Run -> FAIL** (`document --unit` unknown / `TDocBatch` not implemented).

- [ ] **Step 3: Implement `TDocBatch.DocumentUnit`.**

In `src/doc/DRagLint.Doc.Batch.pas`: query the store for all symbols whose file = `AUnitFile` and whose visibility is public/published (reuse the store's symbol query; filter by the symbol's visibility field + `IsPublicSurface` -- a public/published class member, or an interface-section top-level routine/type). For each, call `TDocumenter.BuildFor(store, sym.QualifiedName)` and COLLECT its `Edits`. Facts-only default: `TDocumenter.BuildFor` already emits `TODO: describe.` for a missing summary -- for `Stubs=False`, POST-FILTER so a decl that would produce ONLY a fresh all-TODO comment (no existing doc, no facts) is SKIPPED, but a decl with real facts still gets its managed block. (Simplest correct rule: keep the edit if the merged comment contains a `<!-- drag-lint:auto BEGIN -->` facts block OR the decl already had a doc; drop a pure all-TODO-no-facts create when `Stubs=False`.) Return `TDocBatchResult` with `DeclCount` = public decls seen, `DocCount` = decls contributing an edit. Order edits deterministically (by line descending, so applying earlier edits doesn't shift later line numbers -- match how `FinalizeAndOutput` orders `--fix` edits).

Add the DCCReference `<DCCReference Include="..\doc\DRagLint.Doc.Batch.pas"/>` to `drag-lint.dproj`.

- [ ] **Step 4: Wire the CLI verb `document --unit`.**

In `src/cli/DRagLint.CLI.pas`, extend `DoDocument` (or add `DoDocumentBatch`): when `--unit <file>` is present, build `TDocBatchOptions` from flags (`--stubs`, `--seealso`, `--deprecated`, `--since`), call `TDocBatch.DocumentUnit`, apply via `TTextEditApplier.Apply(Res.Edits, not NoBackup)` when `--apply`, else `RenderDryRun`. `--json`: emit `{unit, declCount, docCount, edits, applied}`. Add a `--unit` field to `TArgs` + parse it. Add a help line. Add `uses DRagLint.Doc.Batch`.

- [ ] **Step 5: Build -> run `run_document_unit.ps1` -> PASS** (2 decls documented, facts-only, idempotent).

- [ ] **Step 6: Guardrail + byte-verify + commit.**
```bash
git add src/doc/DRagLint.Doc.Batch.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/autodoc/run_document_unit.ps1 tests/autodoc/fixtures/docunit/
git commit -m "feat(doc): whole-unit AutoDocument batch (facts-only default) + document --unit"
```

---

## Task 2: `--stubs` opt-in + project-wide batch (`document --project` / `document-all`)

**Files:**
- Modify: `src/doc/DRagLint.Doc.Batch.pas` (add `DocumentProject`)
- Modify: `src/cli/DRagLint.CLI.pas` (`--project`/`document-all` path)
- Create: `tests/autodoc/run_document_project.ps1`
- Create: `tests/autodoc/fixtures/docproj/` (`main.dpr` + 2 units with public decls)

**Interfaces:**
- Consumes: `TClosureResolver.Resolve(dproj): TClosureResult` (Closure.pas) for the file set; `TDocBatch.DocumentUnit` (Task 1).
- Produces: `class function TDocBatch.DocumentProject(const AStore: ISymbolStore; const AProjectFile: string; const AOptions: TDocBatchOptions): TDocBatchResult;` (aggregates `DocumentUnit` over the closure's files; `DocumentAll` variant iterates every file in the index when no project given).

- [ ] **Step 1: Write the failing test.**

Fixtures under `tests/autodoc/fixtures/docproj/`: `main.dpr` (`program main; uses unitA, unitB; begin end.`), `unitA.pas` (a public routine `function Alpha: Integer;`), `unitB.pas` (a public class with a method). `run_document_project.ps1`: index the dir, run `document --project main.dpr --apply` (facts-only) and assert:
- decls in BOTH unitA and unitB gained managed doc blocks (project-wide scope via closure).
- `--stubs` run: a decl with NO derivable summary AND no facts (e.g. a bare `procedure Noop;`) NOW gets a `TODO: describe.` summary -- proving `--stubs` opt-in differs from the facts-only default (which SKIPS it).
- WITHOUT `--stubs` (default): that same `Noop` is NOT documented (no TODO flood).
- IDEMPOTENCY: second `--project --apply` byte-identical.
- `document-all --apply` (no `--project`) documents every indexed unit's public decls.

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement `DocumentProject` + `--stubs` semantics.**

`DocumentProject`: resolve the file set via `TClosureResolver.Resolve(AProjectFile).Files`, call `DocumentUnit` per file, aggregate edits + counts. Thread `AOptions.Stubs` into the facts-only post-filter from Task 1: when `Stubs=True`, KEEP the all-TODO-no-facts create (emit the stub); when `False`, drop it. `DocumentAll`: iterate `store`'s distinct files instead of a closure.

- [ ] **Step 4: Wire `--project` / `document-all` + `--stubs` flag in the CLI** (add `--project`, `--stubs` to `TArgs`; dispatch `document-all`).

- [ ] **Step 5: Build -> run `run_document_project.ps1` -> PASS** (project scope, `--stubs` opt-in vs facts-only default, idempotent).

- [ ] **Step 6: Guardrail + byte-verify + commit.**
```bash
git add src/doc/DRagLint.Doc.Batch.pas src/cli/DRagLint.CLI.pas tests/autodoc/run_document_project.ps1 tests/autodoc/fixtures/docproj/
git commit -m "feat(doc): project-wide AutoDocument batch + --stubs opt-in (facts-only default)"
```

---

## PHASE 2 -- Doc-sources (extend the facts block)

## Task 3: `@deprecated` doc-source (from the directive)

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (add `Deprecated: string` + `DeprecatedMsg: string` to `TDocFacts`; populate in `Build`)
- Modify: `src/doc/DRagLint.Doc.Regions.pas` (render a deprecation `<remarks>` line in the managed block)
- Create: `tests/autodoc/run_doc_deprecated.ps1`
- Create: `tests/autodoc/fixtures/docdep/dep.pas`

**Interfaces:**
- Consumes: `TSymbol.Modifiers` (or the symbol's directive field where `deprecated` is recorded by the parser).
- Produces: `TDocFacts` gains `Deprecated: Boolean; DeprecatedMsg: string;`; `RenderFactsBlock` emits `/// Deprecated: <msg>` (or a bare `/// Deprecated.` when no message) inside the managed block when `Deprecated`.

- [ ] **Step 1: Write the failing test.** `dep.pas`: a public `procedure OldWay; deprecated 'use NewWay';` and a `procedure OldBare; deprecated;`. `run_doc_deprecated.ps1`: index + `document --unit dep.pas --apply`, assert the managed block for `OldWay` contains `Deprecated: use NewWay` and `OldBare` contains a bare `Deprecated.` line; a non-deprecated decl has NO deprecation line. Idempotent.

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement.** In `TDocFactsBuilder.Build`, detect the `deprecated` directive on the symbol (from `Sym.Modifiers`/directive text -- grep how the parser records `deprecated`; it is a routine/type directive). Extract the optional message string literal after it. In `RenderFactsBlock`, emit the deprecation line inside the fenced block (so it regenerates). Ground-truth: only when the directive is actually present.

- [ ] **Step 4: Build -> run `run_doc_deprecated.ps1` -> PASS.**

- [ ] **Step 5: Guardrail + byte-verify + commit.**
```bash
git add src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas tests/autodoc/run_doc_deprecated.ps1 tests/autodoc/fixtures/docdep/
git commit -m "feat(doc): @deprecated doc-source -- managed deprecation note from the directive"
```

---

## Task 4: `<seealso>` doc-source (from the call graph)

**Files:**
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (add `SeeAlso: TArray<string>` to `TDocFacts`; populate in `Build`, capped)
- Modify: `src/doc/DRagLint.Doc.Regions.pas` (render `<seealso cref>` lines in the managed block)
- Create: `tests/autodoc/run_doc_seealso.ps1`
- Create: `tests/autodoc/fixtures/docsee/see.pas`

**Interfaces:**
- Consumes: the index call facts already in `TDocFacts` (`Calls`, resolved callees) + sibling declarations (same parent type).
- Produces: `TDocFacts.SeeAlso: TArray<string>` (capped at `SEEALSO_CAP = 5`, deduped, each a real indexed qualified name); `RenderFactsBlock` emits `/// <seealso cref="X"/>` per entry inside the managed block.

- [ ] **Step 1: Write the failing test.** `see.pas`: a class `TSvc` with `procedure DoA;` that calls `DoB;` and `DoC;` (siblings). `run_doc_seealso.ps1`: `document --unit see.pas --apply --seealso`, assert `DoA`'s managed block has `<seealso cref="...DoB"/>` and `...DoC"/>` (from resolved calls), capped at 5, and WITHOUT `--seealso` there are no seealso lines (opt-in per `IncludeSeeAlso`). Idempotent + deterministic order (sorted).

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement.** In `Build`, when `AOptions.IncludeSeeAlso` (thread the option into the builder, or compute always + gate at render): collect related symbols = the resolved outgoing callees (from `Calls`/call_edges) UNION sibling members of the same parent type; resolve each to a real qualified name; dedupe; sort; cap at `SEEALSO_CAP`. `RenderFactsBlock` emits the `<seealso cref>` lines. Every cref is a real indexed symbol (ground-truth); "related" is a stated heuristic.

- [ ] **Step 4: Build -> run `run_doc_seealso.ps1` -> PASS.**

- [ ] **Step 5: Guardrail + byte-verify + commit.**
```bash
git add src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas tests/autodoc/run_doc_seealso.ps1 tests/autodoc/fixtures/docsee/
git commit -m "feat(doc): <seealso> doc-source -- capped related symbols from the call graph"
```

---

## Task 5: `<since>` doc-source (from git blame, opt-in, degrades silently)

**Files:**
- Create: `src/doc/DRagLint.Doc.GitSince.pas` (isolated git helper)
- Modify: `src/doc/DRagLint.Doc.Facts.pas` (add `Since: string`) + `Regions.pas` (render)
- Create: `tests/autodoc/run_doc_since.ps1`

**Interfaces:**
- Produces: `class function TGitSince.FirstCommitDate(const ARepoDir, AFile: string; ALine: Integer): string;` -- runs `git log -1 --format=%ad --date=short -L <line>,<line>:<file>` (or `git blame -L`) via a spawned process; returns `''` when git is absent, the file is untracked, or the line can't be attributed. `TDocFacts.Since: string`; rendered as `/// <since>YYYY-MM-DD</since>` only when non-empty.

- [ ] **Step 1: Write the failing test.** `run_doc_since.ps1`: create a scratch GIT repo (`git init`, add + commit a fixture unit), index it, run `document --unit <fixture> --apply --since`, assert the managed block has a `<since>` line with a date. THEN run the SAME in a NON-git scratch dir (no `.git`) with `--since` and assert NO `<since>` line appears (graceful degradation -- absence over a wrong fact) and NO crash. Idempotent.

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement `TGitSince`.** Spawn `git` with a bounded timeout; parse the date; ANY failure (non-zero exit, no git, empty output, exception) -> return `''`. In `Build`, populate `Since` only when `AOptions.IncludeSince` AND `TGitSince.FirstCommitDate` returns non-empty. Render only when non-empty. Never emit a guessed date.

- [ ] **Step 4: Build -> run `run_doc_since.ps1` -> PASS** (git present = date; git absent = silent, no crash).

- [ ] **Step 5: Guardrail + byte-verify + commit.**
```bash
git add src/doc/DRagLint.Doc.GitSince.pas src/doc/DRagLint.Doc.Facts.pas src/doc/DRagLint.Doc.Regions.pas src/cli/drag-lint.dproj tests/autodoc/run_doc_since.ps1
git commit -m "feat(doc): <since> doc-source -- git-derived, opt-in, degrades silently when absent"
```

---

## PHASE 3 -- Analysis engine + lint rules

## Task 6: `TDocDrift` engine -- deterministic doc-vs-code diff

**Files:**
- Create: `src/doc/DRagLint.Doc.Drift.pas`
- Modify: `src/cli/drag-lint.dproj` (DCCReference)
- Create: `tests/autodoc/run_doc_drift_engine.ps1` (via a `doc-drift --qname X` diagnostic verb)
- Modify: `src/cli/DRagLint.CLI.pas` (add `doc-drift --qname` diagnostic verb)
- Create: `tests/autodoc/fixtures/docdrift/drift.pas`

**Interfaces:**
- Consumes: `TParsedDoc` (DocComments), `TSymbol` + signature (via `ExtractParamList`/`ParseParamNames`/`SignatureHasReturn` from DocStub), `TDocFacts.Raises` (exception facts), `TDocRegions.RenderFactsBlock` (facts-block staleness).
- Produces:
  ```pascal
  TDocDriftKind = (ddParamRenamedOrRemoved, ddParamMissing, ddParamVolatileMode,
                   ddReturnsButNoValue, ddValueButNoReturns, ddReturnTypeChanged,
                   ddExceptionNotRaised, ddIdentifierGone, ddFactsBlockStale);
  TDocDriftFinding = record Kind: TDocDriftKind; Detail: string; Fixable: Boolean; Line: Integer; end;
  TDocDrift = class
    class function Analyze(const AStore: ISymbolStore; const ASym: TSymbol;
      const ADoc: TParsedDoc): TArray<TDocDriftFinding>;
  end;
  ```
  `Fixable = True` ONLY for `ddParamMissing` (add stub tag), `ddValueButNoReturns` (add `<returns>` stub), `ddFactsBlockStale` (refresh block). All others report-only.

- [ ] **Step 1: Write the failing test.** `drift.pas`: a routine `function F(New: Integer): string;` whose EXISTING doc has `<param name="Old">` (renamed), a `<returns>` (present, OK), plus a `procedure P;` whose doc has a spurious `<returns>` (returns-but-no-value), plus a routine documenting `<exception cref="EFoo">` it never raises. `run_doc_drift_engine.ps1`: `doc-drift --qname drift.F --json` (+ the others), assert the findings array contains `ddParamRenamedOrRemoved` (Old not in sig), `ddParamMissing` (New has no `<param>`), for `P`: `ddReturnsButNoValue`, for the exception case: `ddExceptionNotRaised`; each finding's `fixable` flag matches the rules above.

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement `TDocDrift.Analyze`.** Diff `ADoc.Params[].Name` vs `ParseParamNames(ExtractParamList(sig))`: a doc param not in the sig -> `ddParamRenamedOrRemoved`; a sig param not documented -> `ddParamMissing` (Fixable). Compare a `var`/`out` param whose doc desc reads input-only -> `ddParamVolatileMode` (bounded heuristic: only when the doc text explicitly says "input"/"in" for a `var`/`out` -- else skip; report-only). `SignatureHasReturn` vs `ADoc.ReturnsText<>''`: returns-no-value -> `ddReturnsButNoValue`; value-no-returns -> `ddValueButNoReturns` (Fixable); `ReturnType` differs from a type named in `ReturnsText` (exact-token match only) -> `ddReturnTypeChanged`. `ADoc.Exceptions` cref not in `TDocFacts.Raises` -> `ddExceptionNotRaised`. A summary/remarks identifier (word-token) that is a former param/member name no longer present (high-confidence exact match) -> `ddIdentifierGone`. Managed block text != a fresh `RenderFactsBlock` -> `ddFactsBlockStale` (Fixable). Add the `doc-drift --qname` diagnostic verb (JSON one-line-per-finding) + DCCReference + `uses`.

- [ ] **Step 4: Build -> run `run_doc_drift_engine.ps1` -> PASS.**

- [ ] **Step 5: Guardrail + byte-verify + commit.**
```bash
git add src/doc/DRagLint.Doc.Drift.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/autodoc/run_doc_drift_engine.ps1 tests/autodoc/fixtures/docdrift/
git commit -m "feat(doc): TDocDrift engine -- deterministic doc-vs-code staleness diff"
```

---

## Task 7: `missing-doc` lint rule (public surface only, report-only)

**Files:**
- Create: `src/lint/DRagLint.Lint.DocRules.pas` (houses both new rules)
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (register `missing-doc`)
- Modify: `src/cli/DRagLint.CLI.pas` (dispatch the new rules through the lint path)
- Create: `tests/autodoc/run_missing_doc.ps1`
- Create: `tests/autodoc/fixtures/docmiss/miss.pas`

**Interfaces:**
- Consumes: `ISymbolStore`, `TDocCommentScanner` (does a decl have a doc?), a public-surface predicate.
- Produces: `class function TDocLintRules.RunMissingDoc(const AStore: ISymbolStore): TArray<TLintFinding>;` -- one finding per public/published declaration with NO doc-comment. Rule id `missing-doc`, category `documentation`, DEFAULT SEVERITY warning, **ON by default** (registered without the OFF-by-default flag).

- [ ] **Step 1: Write the failing test.** `miss.pas`: a public `procedure Documented;` WITH a `///` doc, a public `procedure Undocumented;` WITHOUT, and a PRIVATE `procedure Helper;` without. `run_missing_doc.ps1`: `lint --file miss.pas --json` (or `lint-all`), assert exactly ONE `missing-doc` finding, for `Undocumented` -- NOT for `Documented` (has a doc) and NOT for `Helper` (private, exempt). A decl carrying only a drag-lint `TODO: describe.` stub (no real block) still counts as missing? NO -- if it has a managed block it is "documented" for missing-doc; `doc-drift` owns the stale-stub case (spec: no double-report). Assert a stubbed decl is NOT flagged by `missing-doc`.

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement `RunMissingDoc`.** Iterate public/published decls; for each, scan the source above its line for a `///` block (via `TDocCommentScanner` / the existing has-doc check `TDocumenter` uses). Emit a `TLintFinding` (id `missing-doc`) when absent. Public-surface predicate: interface-section top-level types/routines + public/published class members; skip private/protected + implementation-only. Register in `RuleCatalog.BuiltinRegistry` (id, category `documentation`, ON by default). Wire into the lint dispatch so `lint`/`lint-all` run it (respecting ShouldKeep/config gating in `FinalizeAndOutput`).

- [ ] **Step 4: Build -> run `run_missing_doc.ps1` -> PASS.**

- [ ] **Step 5: Guardrail + byte-verify + commit.** (NOTE: this rule is ON by default -- see Task 9 for the guardrail-count investigation; here just confirm the new suite + that the rule appears in `rules --json`.)
```bash
git add src/lint/DRagLint.Lint.DocRules.pas src/lint/DRagLint.Lint.RuleCatalog.pas src/cli/DRagLint.CLI.pas tests/autodoc/run_missing_doc.ps1 tests/autodoc/fixtures/docmiss/
git commit -m "feat(lint): missing-doc rule (public-surface-only, report-only, ON by default)"
```

---

## Task 8: `doc-drift` lint rule (report-only + `--fix` for the safe subset)

**Files:**
- Modify: `src/lint/DRagLint.Lint.DocRules.pas` (add `RunDocDrift`)
- Modify: `src/lint/DRagLint.Lint.RuleCatalog.pas` (register `doc-drift`, mark fixable)
- Modify: `src/cli/DRagLint.CLI.pas` (drift `--fix` routes the fixable subset through `TDocBatch`/`TDocRegions`)
- Create: `tests/autodoc/run_doc_drift_rule.ps1`

**Interfaces:**
- Consumes: `TDocDrift.Analyze` (Task 6), `TDocCommentScanner`/`TParsedDoc`, `TDocRegions.MergeComment` (for the fix path), the fixable-rule registry (`IsFixableRule`).
- Produces: `class function TDocLintRules.RunDocDrift(const AStore: ISymbolStore): TArray<TLintFinding>;` -- one finding per drift signal on a documented decl. Rule id `doc-drift`, category `documentation`, ON by default, `fixable=true` (its safe subset only). The `--fix` path applies ONLY `Fixable=True` findings (facts-block refresh + missing param/returns stubs) via `MergeComment`; report-only findings are never auto-edited.

- [ ] **Step 1: Write the failing test.** Reuse `docdrift/drift.pas`. `run_doc_drift_rule.ps1`: `lint --file drift.pas --json`, assert `doc-drift` findings for the renamed-param + spurious-returns + not-raised-exception. Then `lint --file drift.pas --fix`, assert: the facts-block was refreshed and the missing `<param name="New">` stub ADDED (fixable subset applied), but the renamed `<param name="Old">` prose was NOT deleted/rewritten (report-only -- human decides). IDEMPOTENCY: a second `--fix` is byte-identical AND re-analysis reports no fixable drift.

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement `RunDocDrift` + the fix route.** `RunDocDrift`: for each DOCUMENTED public decl, parse its doc, call `TDocDrift.Analyze`, emit a `TLintFinding` per signal (message from `Detail`, `fixable` flag from the finding). Register `doc-drift` in the catalog (ON, fixable). In the `--fix` path (`FinalizeAndOutput`/the fix block), for a `doc-drift` finding with `Fixable=True`, build the repaired comment via `TDocRegions.MergeComment` (refresh block + add missing param/returns stubs) and emit a `TTextEdit`; skip non-fixable findings. Add `doc-drift` to the fixable-rule registry (`FIXABLE_RULE_IDS`).

- [ ] **Step 4: Build -> run `run_doc_drift_rule.ps1` -> PASS** (report all, fix only safe subset, idempotent).

- [ ] **Step 5: Guardrail + byte-verify + commit.**
```bash
git add src/lint/DRagLint.Lint.DocRules.pas src/lint/DRagLint.Lint.RuleCatalog.pas src/cli/DRagLint.CLI.pas tests/autodoc/run_doc_drift_rule.ps1
git commit -m "feat(lint): doc-drift rule (report-only + --fix for the mechanically-safe subset)"
```

---

## PHASE 4 -- Integration, IDE, measurement, spike

## Task 9: Guardrail investigation for the two ON-by-default rules

**Files:**
- Modify: (only if a suite legitimately shifts) test expectation files OR a `--no-preprocess`-style scoping; otherwise NONE.
- Create: `tests/autodoc/run_docrules_catalog.ps1` (locks the rule count + fixable flags)

**Interfaces:** consumes the two new rules (Tasks 7-8). NO new production code unless a guardrail regression demands it.

- [ ] **Step 1: Run the FULL battery** on the staged exe: `tests\lint\run_lint_tests.ps1`, store, autodoc (all `run_*`), autofix, callresolve, + the 9 preprocess harnesses. `missing-doc`+`doc-drift` are ON by default, so a lint/autofix fixture that has undocumented or drifted decls may now emit NEW findings -> the lint count may move from 154.

- [ ] **Step 2: Investigate EACH change.** For every suite whose count/output changed: is it a CORRECT new finding (the fixture genuinely has an undocumented public decl / a drifted doc -> update the expectation, documented) or a REGRESSION (a rule firing where it shouldn't -> fix the rule's predicate)? Most lint/autofix fixtures are tiny + undocumented, so `missing-doc` WILL fire on them -- decide per suite: (a) update the expected count, or (b) scope the guardrail lint invocation to exclude the two doc rules (e.g. run the pre-existing suites with the doc rules disabled via config, since those suites test OTHER rules, and cover the doc rules in their OWN new suites). PREFER (b) for the pre-existing rule suites -- they test unrelated rules and shouldn't be perturbed by a new default -- and rely on the dedicated `run_missing_doc`/`run_doc_drift_rule` suites for doc-rule coverage. Document the decision.

- [ ] **Step 3: Add `run_docrules_catalog.ps1`** -- assert `rules --json` lists `missing-doc` + `doc-drift`, both `enabled=true` (ON by default), `doc-drift` `fixable=true`, `missing-doc` `fixable=false`; assert the total built-in rule count grew by exactly 2.

- [ ] **Step 4: Re-run the FULL battery -> all green** (with the documented expectation updates / scoping).

- [ ] **Step 5: Commit.**
```bash
git add tests/ src/
git commit -m "test(lint): guardrail investigation for missing-doc+doc-drift ON-by-default (+ catalog lock)"
```

---

## Task 10: IDE menu -- "Document unit" / "Document project" + doc-drift Fix-it

**Files:**
- Modify: the IDE plugin structure/menu unit (grep the plugin dir for the existing "Document it" menu item added in Chunk 1, e.g. `StructureForm.pas` or the plugin's context-menu unit).

**Interfaces:** consumes the `document --unit`/`--project` verbs (Tasks 1-2) + the `doc-drift` rule's fixable findings (Task 8) via the existing Fix-it wiring.

- [ ] **Step 1: Locate the Chunk-1 "Document it" menu item** (grep the plugin source for `Document it` / the `document --qname` spawn). Model the new items on it.

- [ ] **Step 2: Add "Document unit" + "Document project" menu items** that spawn `document --unit <activeFile> --apply` / `document --project <dproj> --apply` (via the shared `DragLintExe` resolver -- the Win64-default resolver from v0.86) and reload the buffer, mirroring the Chunk-1 item's spawn+reload pattern.

- [ ] **Step 3: Confirm `doc-drift` findings surface with Fix-it.** The `doc-drift` rule is `fixable`, so the existing Fix-it/Fix-all context menu (AutoFix) already offers a fix for its findings -- verify no extra wiring is needed (the fixable-rule registry drives the menu). If the Fix-it menu keys off `FIXABLE_RULE_IDS`, adding `doc-drift` there (Task 8) is sufficient; note that in the report.

- [ ] **Step 4: Build the plugin BPL** (the plugin build recipe -- the plugin `.dpk`, not the CLI exe). Confirm it compiles. IDE LIVE SMOKE is DEFERRED TO USER (as with prior IDE work -- do NOT run deploy-staged.bat; the user reopens the IDE).

- [ ] **Step 5: Commit.**
```bash
git add <plugin source + bpl if built>
git commit -m "feat(ide): Document unit/project menu items + doc-drift Fix-it (live smoke deferred to user)"
```

---

## Task 11: Full battery + measure the first-run `missing-doc` wave + `--help` finalize

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (ensure `document --unit/--project`, `document-all`, `doc-drift`, and the doc-source flags have `--help` lines)
- Create: `tests/autodoc/MEASUREMENT-missing-doc.md` (the measured first-run wave)

- [ ] **Step 1: Finalize `--help`.** Confirm every new verb/flag (`document --unit`, `document --project`, `document-all`, `--stubs`, `--seealso`, `--deprecated`, `--since`, `doc-drift`) has an accurate help line, formatted like the surrounding entries. Rebuild if edited.

- [ ] **Step 2: Full battery** on the staged exe -- lint (updated count), store 16, autodoc (all new + existing), autofix 9, callresolve 12, + the 9 preprocess harnesses -> ALL green.

- [ ] **Step 3: MEASURE the ON-by-default first-run wave.** Index drag-lint's own `src/` to a scratch DB, run `lint-all` with the two new rules ON, and RECORD: the `missing-doc` finding count and the `doc-drift` finding count on drag-lint's own tree. Write `tests/autodoc/MEASUREMENT-missing-doc.md` with the numbers + a one-line honest read ("public-surface-only keeps missing-doc to N; the wave is/ isn't reasonable for an alpha default"). This is the spec's data-driven checkpoint -- if the number is unreasonable, FLAG it for the controller/user before shipping (do not silently ship an unusable default).

- [ ] **Step 4: Commit.**
```bash
git add src/cli/DRagLint.CLI.pas tests/autodoc/MEASUREMENT-missing-doc.md
git commit -m "chore(doc): finalize AutoDocument verbs/help + measured missing-doc first-run wave"
```

---

## Task 12: DocInsight-collection spike (investigation, findings note)

**Files:**
- Create: `docs/lint/SPIKE-docinsight-collection.md`

**Interfaces:** none (investigation only, no code).

- [ ] **Step 1: Investigate** RAD Studio's documentation-output option (DocInsight / XML-doc emission): does the compiler collect docs into a specified folder during a build, what is it supposed to emit, how is it configured (`.dproj` option / a `dcc` switch), and why did it give the user no meaningful results. Use the delphi docs / docwiki MCP + the local IDE install to confirm. Keep it bounded -- a short investigation, not a build.

- [ ] **Step 2: Write `docs/lint/SPIKE-docinsight-collection.md`** -- what it emits, how it's configured, why it underdelivered, and a recommendation: "drag-lint supersedes the built-in" vs "drag-lint feeds/augments it (emit compatible XML)." This feeds a FUTURE decision; it does NOT change this milestone's code.

- [ ] **Step 3: Commit.**
```bash
git add docs/lint/SPIKE-docinsight-collection.md
git commit -m "docs(spike): RAD Studio DocInsight-collection investigation + recommendation"
```

---

## Task 13: Final whole-branch review + publish decision (controller-driven)

- [ ] **Step 1: Final whole-branch review** (superpowers:requesting-code-review) over the diff since the spec commit. Focus: no-fabrication holds everywhere (batch facts-only default, `<since>` absent-over-wrong, drift never rewrites prose); idempotency (batch + `doc-drift --fix` byte-identical on re-run); the two ON-by-default rules' first-run wave is measured + reasonable (Task 11); `missing-doc`/`doc-drift` do not double-report; public-surface-only scoping is correct; the fixable subset is genuinely mechanically-safe; encoding/CRLF; full battery green.
- [ ] **Step 2: PAUSE for user sign-off** before any version bump / release. Then release as **v0.93.0-alpha** (release commit = CLI.pas VERSION + CHANGELOG + BACKLOG per the v0.87 convention; tag; win64/win32 CLI-only zips; GitHub release), if approved.

---

## Self-review notes (author)

- **Spec coverage:** batch unit (T1) / project + `--stubs` opt-in facts-only default (T2) / `@deprecated` (T3) + `<seealso>` (T4) + `<since>` opt-in-degrades (T5) doc-sources / `TDocDrift` deterministic engine incl. param+returns+exception+identifier+facts-stale, volatile `var`/`out` mode, return-type change (T6) / `missing-doc` public-surface-only ON-by-default (T7) / `doc-drift` report+fix-safe-subset ON-by-default (T8) / ON-by-default guardrail investigation + noise mitigation (T9) / IDE menus + Fix-it (T10) / measured first-run wave + help (T11) / DocInsight spike (T12) / final review + publish (T13). All spec sections mapped.
- **Type consistency:** `TDocBatchOptions`/`TDocBatchResult`/`TDocBatch` (T1) used by T2. `TDocFacts` extended with `Deprecated/DeprecatedMsg` (T3), `SeeAlso` (T4), `Since` (T5) -- each rendered by `RenderFactsBlock`. `TDocDriftKind`/`TDocDriftFinding`/`TDocDrift.Analyze` (T6) consumed by `RunDocDrift` (T8). `TDocLintRules.RunMissingDoc` (T7) / `RunDocDrift` (T8) both in `DRagLint.Lint.DocRules.pas`. `MergeComment`/`RenderFactsBlock` signatures unchanged from Chunk 1 (extended internally).
- **Phasing:** structural (T1-T5, T7) lands a complete "finished" batch+sources+missing-doc even if T6/T8 drift proves fuzzy; `doc-drift` (T6/T8) is the bounded final analysis phase; T9-T13 integrate/measure/review.
- **Flagged soft spots:** (1) ON-by-default noise -- T9 investigates + prefers scoping the pre-existing suites, T11 measures the wave (data-driven checkpoint). (2) `<since>` git dependency -- T5 mandates silent degradation + a non-git test. (3) volatile-param + identifier-drift are BOUNDED heuristics (report-only, high-confidence only) -- T6 keeps them conservative to avoid false drift. (4) facts-only-default post-filter (T1) is the subtle "don't flood TODOs" rule -- its fixture proves the default vs `--stubs`.
- **Build gotchas encoded:** ASCII/CRLF byte-check new files; DCCReference per new unit; delphi-build recipe; neutral test CWD; staged exe; no-fabrication + idempotency asserted per relevant task.
