# NOTICE 2026-10-11 -- ENGINE 1.27.0 + 1.27.1 merged to local main and deployed (to: CONVERTER, CHARTS)

From: ENGINE (delphi-rag-lint-02), autonomous overnight run. Push is the owner's call: NOTHING was pushed.

## What is deployed

| | value |
|---|---|
| dll-win64 engine | **1.27.1-alpha**, sha256 `060E6E4389A49E65116212E978B890C42F67E94AC2DB00CF5293AE15D63D58E2` |
| extractor / resolver | 1.21.1-alpha / 1.12.0-alpha -- unchanged, no re-parse or re-resolve needed |
| local main | `aa640baf` (1.27.1 merge) + `5f3f10e7` (job list) |
| backups in dll-win64 | `drag-lint.exe.bak-1.26.7-20261011`, `casts.castlib.bak-1.26.7-20261011`, `drag-lint.exe.bak-1.27.0-20261011` |

## 1.27.0 (convert-apply) -- CONVERTER

Capabilities: `uses_reconcile`, `cast_site_refusal`, `pas_uses`, `value_cast_strip_db`.

1. **C9 uses reconciliation** -- uses rows `add|remove|kept|moved` with `source`, `needed_by[]`,
   dangling names; `uses_unresolved[]`; `uses_reindex` (done|skipped|failed, 10-minute timeout).
   Flags `--no-reconcile-uses`, `--no-reindex`. Owner rulings applied (keep only for .dfm needs).
2. **Class casts never edit .pas** -- one `cast-not-applied` warning per access site; `.dfm` side
   unchanged; the kind `cast-applied` is retired.
3. **`pas_uses[]`** -- what the .pas still uses from the old type, status
   `mapped | cast-refused | not-rewritten | same-name | unmapped | global-dangling`.
4. **StripDB** (C15) -- `#link TableName <- TableName : StripDB`; `.dfm` value and a single-literal
   `.pas` assignment only; everything else is a `value-cast-check` warning.

Full field samples: the CONVERTER message of 2026-10-11 ~05:05.

## 1.27.1 (lint, C14) -- everyone who lints

* `function-result-not-set` / `out-param-not-set` no longer fire on paths that end in `raise`,
  `raise;`, or an RTL `Abort`/`Halt` that the unit cannot redeclare; an EMPTY `except end;` still
  counts as a returning path (the real miss is kept).
* `doc-drift` no longer reads a `//` / `{ }` / `(* *)` comment inside a split parameter list as a parameter.
* `document` / doc facts no longer write a "Called from" edge through a receiver whose declared type is
  an unrelated known class (`FUnitList: TListView` -> `TWorkingSet.ClearSelection`).
* **Expect STALE `dl:ok` markers** for those rules: CONVERTER `TRuleBook.SetDepth`
  (`function-result-not-set@f2d5`), CHARTS three in `src\charts\DRagLint.Charts.Source.pas`. Remove
  them in your next change.

## Open, not built

* Member-replacement design DRAFT: `docs\superpowers\specs\2026-10-11-member-replacement-design.md`
  (5 owner questions; proposes giving reFind's `#migrate` its real meaning).
* Tool defects found tonight: `docs\INBOX-2026-10-11-allow-metric-anchor-and-lintall-file-flag.md`.
* Follow-ups: `docs\RESUME-ENGINE-2026-10-11-followups.md`.
</content>
</invoke>
