# 150 TL -- TAILS (every actionable 147-150 tail, grouped file-disjoint)

Built 2026-11-09 ~20:45 by lane TL from: lanes\147|148|149|150\*\REPORT.md, the 4 LEDGER.md, 150\PLAN.md Fixed facts,
150\BACKLOG-AFTER-150.html, 150\DOC2\REPORT.md, 150\SW\REPORT.md, 150\INT\REPORT.md, 150\MS-A\REPORT.md.
Base for every group: the INT head (lane/150-INT). Excluded on purpose (owner 20:20): PF2b, live GUI/IDE/VM proofs,
owner decisions (W1 comment table, LINT-REPORT default, GA-1, EX1 fold, RB-5, P6 hub flip, SCHEMA 24 confirm),
owner chores, other teams' files, parked items (PLAN Fixed facts / BACKLOG section 6), MS-B finishers (1b/1c/parity).

Hashed = touches a unit in the extractor or resolver fingerprint -> ledger `REPIN-NEEDED <lane> <units>`; INT re-pins once.

## Groups (file-disjoint; hot files named; each <= 60 min)

| group | wave | lane | item | files (HOT in caps) | est min | model | hashed |
|---|---|---|---|---|---|---|---|
| G1 | 150 | SC | SC-1: ~30 read-only `TSQLiteSymbolStore.Create` sites below READ_MIN -> refuse with SchemaUnreadableReason (new `CreateReadable` raising ESchemaUnreadable; OpenReadable for the probes). RED guard tests\autotest\run_schema_unreadable_openers.ps1 (written; base: no AV on menu-tree/forms-csv/unwith with intact tables -- they silently answer a v22 index; butterfly already refuses) | STORAGE.SQLITE.PAS (new class fn only), FormsMap, MenuTree, MenuTree.Dfm, MCP.Server (1759), Refactor.Unwith, Refactor.MultiProjectRename, Index.Drift, Charts.* (13 units), CLI.PAS 2388 / 2426 / 5782 only | 60 | TL (session) | yes (Storage.SQLite) |
| G1-final | 150 | SW/INT | doc-drift facts pass (~409 "managed facts block out of date": TreeSitter* 200, AstChecks 31, CycleEdge 17, Doc.Regions 16, 67 files): `document --unit <u> --apply --no-backup` per unit, comment-only, reindex, `lint-all --rule doc-drift` -> 0 or residuals named | the 67 units of SW's lint-all list (comment lines only) | 45 + 1 HEAVY lint-all | TL (session), LAST: run on the INT head AFTER G2..G9 merge (facts are derived from code; an earlier pass goes stale again) | yes (comment-only re-pin) |
| G2 | 150 | CF | `ProjectRules` message suffix "(in include X, line N)": TUsesAuditRow carries no origin; read the N-06 use-origin columns (HasUseOriginCols) into the row and append the suffix | src\lint\DRagLint.Lint.ProjectRules.pas, src\lint\DRagLint.Lint.UsesAudit.pas (TUsesAuditRow) (not CLI.pas) | 45 | sonnet | no |
| G3 | 150 | EX3 | EX3-a: `library X;` .dpr root gets a root symbol like program/package; top-level decls parented to it (fixture: library + exports, `sql` on symbols.parent_id) | PARSER.DELPHI13.PAS (root-symbol emit region only), its emit fixture | 45 | session | yes |
| G4 | 150 | EX3/RS1 | EX3-b: dotted type_use `var V: uEx3Types.TEx3Runner` symbol_id NULL; RS1 routine-local typed-const receiver `CLocal.Alpha` unbound. Fixture-only proof; INT-RES-AB re-run by INT | INDEX.CALLRESOLVER.PAS (type_use binding + receiver lookup regions) | 60 | session | yes |
| G5 | 150 | EX3/RF | EX3-c: RedundantCast.pas:603 counts `parent_id IS NULL` as "global"; .dpr globals now parent to the program symbol -> count program-parented value decls as global, exclude the program symbol itself; fixture with a .dpr global | src\refactor\DRagLint.Refactor.RedundantCast.pas + fixture | 20 | sonnet | no |
| G6 | 150 | DF2 | Parser.DFM.pas residual lint (7 of 15 left after DF2): fix or dl:ok with reason each | PARSER.DFM.PAS | 30 | sonnet | yes if the emit path changes (lint-only edits: no) |
| G7 | 150 | CY3 | `query implementors` -> "unknown query subcommand" while the global verb table names it: route `query implementors` to the existing implementors verb (alias) + --help / README / AI-USAGE line; run_docs_sync_guard | CLI.PAS query-subcommand dispatch region only, README.md, docs\AI-USAGE.md, features entry | 25 | sonnet | no |
| G8 | 150 | INT/TOOLS | run_charts_tests fails 69 checks from a non-repo cwd: anchor fixture paths on $PSScriptRoot (Set-Location repo root at start) | tests\charts\run_charts_tests.ps1 | 15 | haiku | no |
| G9 | 150 | HG | HG-4 run_write_refs_bind flake (UNPROVED): point -Exe at the wt exe, run 20x in 2 parallel loops under load, record the failing check number + engine path; fix the check if it fails, else close UNPROVED-with-numbers | tests\callresolve\run_write_refs_bind.ps1 | 40 (LIGHT x20) | sonnet | no |
| G10 | 150 | CQ/RT | RT Micronite redundant-cast miss (UNPROVED): `lint --fix --fix-rule redundant-cast` on a COPY of the Micronite DB with the INT exe; read the new library NOTE; if several manifest library sections for the platform -> fix the pick (first EXISTING one wins -> the one whose platform+compiler match) | read: _copies + Micronite; write only if a fix: CLI.PAS lint-fix library load (CQ region) | 45 incl. 1 HEAVY | sonnet | no |
| G11 | 150 | MS-A | MS-A (3): string-equality-comparison +38 / doc-drift +20 / deep-nesting +5 vs 1.46 on CLIENT: sample 10 new each, classify FP / TP / noise; an FP class -> rule fix with fixture + positive control | read: _copies\client.sqlite (copy to scratch); write: the rule's rules\*.scm or Lint unit only if FP | 60 incl. 1 HEAVY lint-all | session | no |
| G12 | 150 | PF2b | LANE-RULES + setup-lane.ps1 do not copy drag-lint.json beside the wt exe (A/B arms lose the library DBs) | C:\TEMP\claude\lanes\150\LANE-RULES.md, setup-lane.ps1 (controller files, not the repo) | 10 | controller | no |

## Optional (actionable, low value; dispatch only if a slot is idle)

| group | lane | item | files | est | model |
|---|---|---|---|---|---|
| G13 | W1 | index summary line `parse-errors=N` (the index is silent on ERROR trees); check every summary-line consumer in tests\autotest first | CLI.PAS index summary print + docs | 45 | sonnet |
| G14 | CF | CF-1 residual: FormsMap rewire to dfm_objects (no property rows in dfm_objects -> needs a DFM emit change + re-parse) | Parser.DFM emit, Storage dfm_objects, FormsMap (rebase on G1: FormsMap 3047 one-line overlap) | 90+ (over the cap) | session |

## Hot-file map (one group per region)
- Storage.SQLite.pas: G1 only (new class function next to OpenReadable).
- CLI.pas: G1 (2388/2426/5782), G7 (query dispatch), G10 (lint-fix library load, only if a fix), G13 (index summary). Non-adjacent regions; merge in that order.
- CallResolver.pas: G4 only. Parser.Delphi13.pas: G3 only. Parser.DFM.pas: G6 only.
- G1-final runs last and touches only /// facts lines; it re-reads the merged tree.

## Not actionable (measured / closed) -- for the record
PS 4 parse failures (broken source / dcc rejects / platform-foreign); DQ-3 (closed with reason); DF2 corpus 39 = taint rules;
LSP C13 516 ms (environmental); HG-5 corpus-roots (grammar repos, owner); 147 PF bound-ref perf (follows PF2 = PF2b);
GV top-N unlinked notes (Graph repo, live proof); DOC2 "E1" (informational).
