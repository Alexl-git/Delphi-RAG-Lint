# Engine 1.20.6-alpha merge notice -- for the converter-editor team

Engine: branch fix/1.20.6-editor-gaps, engine HEAD f282ea0d, merged into LOCAL main as 61cac930 (NOT pushed; GitHub release is an owner step) (includes Task 6 -- the stale-.dfm-span refusal -- and the final-review fix wave: exact span end, truncated .dfm refused, R26). Measurements below were taken at 723ea0bd; old = pre-redesign 14396852.
Deployed build: `drag-lint --version` = `drag-lint 1.20.6-alpha`, deployed 2026-10-05 03:22 to C:\Projects\Delphi-RAG-lint\third_party\dll-win64\, drag-lint.exe SHA256 `4AE891098DD0BE20EEA844CC5FD13BCCD86300708290E05E65594F49F5ECA77A` (41,749,746 bytes).
All runs on scratch COPIES of the DBs; wall-clock, one run each, other engine runs sometimes overlapped (see notes).

## Measurements

| Case | OLD | NEW | classes_built (new) |
|---|---|---|---|
| BDE-to-FireDAC.rules, convert-apply dry run, dmCPData (TTable/TQuery as `object`) | did not finish (capped at 1200 s) | 26.5 s, exit 0, 0 rule errors, 16 unreachable warnings | 33 |
| Same book, convert-validate --from TQuery --to TFDQuery | 408.6 s, exit 1 | 17.9 s, exit 1 | n/a |
| Real dmCPData.pas (inherited TTable/TQuery) convert-apply | refused (R6), same as new | 0.6 s, exit 1, `refused: true` | 0 |
| TabcToggleBtn book, VARINSP, convert-validate | 190.1 s, exit 0 | 14.9 s, exit 0 | n/a |
| TabcToggleBtn book, VARINSP, convert-apply dry run | 129.8 s, 20/20 instances, 60 edits, 0 rule errors | 16.7 s, 20/20, 60 edits, 0 rule errors | 4 (old: trees_built=2) |
| proptree TFDQuery depth 3 (JSON, 6,410 nodes) | 94.9 s contended / ~45 s uncontended (old counts include private: 11,046 nodes) | 12.9 s | n/a |
| proptree TFDQuery depth 4 (JSON, 26,107 nodes) | 376.5 s (old: 45,807 nodes) | 13.6 s | n/a |
| proptree TFDQuery depth 5 (JSON, 101,063 nodes) | 447-514 s via a file redirect; 80.3 s as the editor's pipe drain sees it | 14.0 s (14.4-14.7 s via the drain); output byte-identical to the old engine's depth-5 JSON (37,258,916 B) | n/a |

Notes
- BDE validate: the 145 error lines are identical in old and new (mappings of OTHER blocks, checked against the single --from/--to pair; by design). convert-apply validates per block and has 0 errors. Plain `convert-validate` without --from/--to returns OK in 0.6 s.
- New BDE convert-apply: 16 `unreachable` warnings (FieldOptions.* is protected in Data.DB.TDataSet), exit 0. Old engine: the 20-minute cap was hit (Task 2 earlier: 68 min, killed).
- Old runs were run concurrently with each other (2 at a time), and the new proptree runs overlapped them; old figures are upper bounds.
- VARINSP is not a member of Micronite2027.sqlite. For the measurement the scratch copy of the unit + dfm was indexed INTO the scratch DB copy; without the .dfm in the index, convert-apply skips all 20 instances ("not covered by any supplied --db").
- Micronite2027.sqlite (real): size 171552768, mtime 2026-09-29T16:22:30Z, unchanged before and after.

## Editor-facing changes

1. Default depth: the old effective default was 3 (the documented 6 was dead); it is now 5 (`--depth N` > book `#depth N` > 5). Depth is the class-recursion budget: a K-segment path needs depth >= K-1.
2. Private and strict private members are never shown or resolved (proptree nodes vanish; DFM paths: leaf published, intermediate hop published or public+class-typed).
3. `#depth N` (1..10, at most one per book) must be added to ConvRules.Model for round-tripping. A bad `#depth` in a `--rules` book exits 2 in proptree / convert-scaffold; convert-validate reports it as a normal `line N:` error.
4. apply/1: `trees_built` is replaced by `classes_built`.
5. `--validate-all-blocks` and `blocks_not_validated` are gone: every `#convert` block is always validated (flag now exits 3 as unknown).
6. apply/1 `unreachable[]`: always present, `[]` when none; each element has keys in order `line, path, member, visibility, class, reason ("unreachable"), message`. Text: `line N: warning: <path>: <Member> is <visibility> in <DeclaringClass>; never applied unless a descendant class changes its visibility`. Also appended to `warnings[]` and as items[] kind `rule-path-unreachable`. Only unreachable TARGETS are stripped; an unreachable `#when` source skips the whole mapping for that block; filtering is per block. convert-validate prints them as text only (no JSON mode); hidden convert-reemit gets top-level `unreachable[]`.
7. Refusals: text mode prints exactly one `REFUSED: <reason>` line (it replaced `ERROR:`); JSON has `refused` (bool, always present) and `reason` (always present, `""` unless refused); `error` still carries the same text; exit 1, NOTHING written (neither .pas nor .dfm). Key on `refused == true`, never on `error` being non-empty. Exact reason texts:
   - R6 (inherited/inline object of a From type): `inherited instances of <T> are not converted yet -- unit not changed`
   - unit rules, entry inside a conditional: `<Unit>.pas: "<Entry>" sits inside a conditional ({$IF...}) region of the <interface|implementation> uses clause -- unit rules not applied to this unit` (siblings with the same `<Unit>.pas: <why> -- unit rules not applied to this unit` frame: a removal that would cross a conditional directive, a clause holding a directive that would have to be rewritten whole, no unconditional entry to add after, not a unit, no interface/implementation section, a clause that cannot be read)
   - T6 stale .dfm span: `<Name>: index is stale for this .dfm -- reindex` -- the recorded span no longer opens `object|inherited|inline <Name>:`, its FIRST `end` at the opener's indent is not the recorded end line (a block that lost lines and now ends on a sibling's `end`), or (fix wave) the .dfm was cut short after indexing so the span runs past its end (this used to skip that one instance and convert the rest).
   - R26 (fix wave): `<rule> would leave <N> unconverted instance(s) of <Type> -- unit not changed`, where `<rule>` is the book rule as the `uses[].rule` field spells it, e.g. `#unuse LibA would leave 1 unconverted instance(s) of TSrcBtn -- unit not changed` / `#useswap LibA -> LibB would leave 1 unconverted instance(s) of TSrcBtn -- unit not changed`. Fires when a planned removal (#unuse, or #useswap's Old) targets the unit that DECLARES (per the index: the From type's declaring file) the From type of a #convert instance that stays unconverted -- skipped for any reason, or excluded by `--only` (also when `--only` excludes every instance and the unit rules would otherwise run alone).
   - NOT refusals (`refused: false`, `reason: ""`): freshness-guard failures, rule-validation errors, missing files, the planner's internal defect, and UNREACHABLE warnings.
8. `--progress-interval S`: proptree and convert-scaffold only; off by default (0); one JSON line on stderr every S s, shaped `{"progress":{"elapsed_s","verb","class","depth","max_depth","classes_done","classes_queued","nodes"}}` (e.g. `{"progress":{"elapsed_s":12.3,"verb":"proptree","class":"<qname>","depth":2,"max_depth":5,"classes_done":41,"classes_queued":7,"nodes":3114}}`); convert-apply / convert-validate reject it with exit 3. Bad value exits 2.
9. `info --json` capabilities: `apply_unit_rules`, `book_depth`, `progress_lines`, `lazy_validate` are JSON `true`.
10. Merged-stream safety (T2i, 723ea0bd): convert-apply (dry run and --apply), convert-reemit, info --json, query --name --json, outline --format json, sql --json, proptree and convert-scaffold write stdout in one piece after flushing stderr, so a merged pipe sliced first `{` .. last `}` parses. proptree JSON output speed: depth-5 TFDQuery 80 s -> about 14.7 s as the editor sees it.
11. Unit rules (Task 1) -- the full apply/1 contract:
    - `info --json` -> `capabilities.apply_unit_rules: true`.
    - `component_part` (always present): `"applied"` | `"skipped-no-dfm"` | `"skipped-no-convert-rules"` | `"skipped-no-instances"`; `""` when the run stopped before planning -- the R6 refusal, a rule-validation error, a freshness failure. For `skipped-no-dfm`, `dfm` is `""`.
    - `uses[]` (always present): `{"action":"remove"|"add","unit","section":"interface"|"implementation","line","rule"}`; `line` is 1-based in the unit AS READ; `unit` as written in the unit (remove) / in the book (add); `rule` is `#unuse Old` | `#use New` | `#useswap Old -> New1, New2`. The #convert blocks' own uses-add is NOT a row (it is counted in `edits_count`).
    - `uses_removed`, `uses_added`: counts of `uses[]` by action.
    - R4: a `#useswap` makes NO edit when the unit does not use Old (its News are not added); `#use` is unconditional (added to the implementation uses when absent from both clauses; a clause is created when there is none).
    - `--only` filters INSTANCES, never unit rules; since the fix wave a removal that `--only` (or a skipped instance) would make unsafe is refused by R26 instead of breaking the compile with E2003.
    - Text mode: `dfm: none -- component part skipped, unit rules only` (or the no-#convert / no-instance variants), then `Uses: N removed, M added` and one line per change.
12. Behaviour changes in path resolution and books:
    - a path THROUGH a referenced component (`Connection.X`) is NOT FOUND (references are leaves);
    - a hop through a non-class member is NOT FOUND (R15);
    - a private redeclaration shadows the ancestor's member (R11), so the ancestor's member is not reached through it;
    - books scaffolded with `--surface pas` now validate, with warnings (R12 supersedes R10);
    - the 16 unreachable lines in BDE-to-FireDAC.rules are named: 274-277, 374-377, 478-485.
13. Under `--format json`, two paths still print TEXT, not JSON: the missing-.dfm exit (a book with no unit rules on a unit with no sibling .dfm, exit 1) and the exit-2 usage paths (bad arguments, unreadable rules file). Slice-first-`{` parsing finds no JSON there; treat a non-JSON reply with exit 1/2 as a failure.
14. From-only headers (R27, fix wave): the engine trimmed the line before splitting on ` -> `, so `#convert TFoo -> ` (trailing space, no To -- the form the editor writes while authoring) was read as FromType `TFoo ->`. Now the split matches the trailing arrow: FromType `TFoo`, ToType EMPTY, and the header is a normal `line N:` parse error -- `#convert TFoo has no To type` (also for `#convert TFoo` with no arrow). `#useswap X -> ` (no New unit) is `#useswap X has no replacement unit`. convert-validate exits 1 with that line; the text `TFoo ->` never appears as a type. A normal `#convert A -> B` / `#useswap Old -> New` parses unchanged.
15. R26 does not fire when the From type does not resolve in any --db (R7 reports that type on the block line instead); only resolved From types are checked against a planned removal.
16. Verification: full battery on f282ea0d 630/637 (the 7 = known environment failures + run-order flakes that pass alone); `info --json` capabilities on the deployed exe: apply_unit_rules, book_depth, progress_lines, lazy_validate all true.
