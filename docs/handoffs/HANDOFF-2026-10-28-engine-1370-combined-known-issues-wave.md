# HANDOFF 2026-10-28 (10:50) -- ENGINE: 1.37.0 combined (all streams) + known-issues wave

Supersedes for ENGINE: `HANDOFF-2026-10-28-engine-1370-int-plus-backlog-lanes.md` (detail + gotchas still valid
there; read its UPDATE 13:40 / 15:00 for the INT2 review list) and `HANDOFF-2026-10-27-engine-gaps-wave-lanes-merged-int-next.md`.
Ledger (source of truth for lanes): `C:\TEMP\claude\lanes\gaps\LEDGER.md` -- read its tail.
Combined all-team backlog: `docs\BACKLOG-AFTER-1.37.0.md` (gitignored, main tree; Upcoming 22 / Known 17 / Parked 24 / Ideas 15).

## Owner ruling (2026-10-28 morning)
Resume ENGINE 1.37.0; fold all other open handoffs into one view; fix as many "Known issues" as possible in THIS
release, highly parallel subagents, Fable plans. Standing: anything forcing a re-parse goes into 1.37.0; complete >
early; push code when green, publish only on go; sonnet for plan-designed lanes, haiku mechanical.

## Verified state 10:50 (do not redo)
| item | state |
|---|---|
| main | db14a97a = 68bf8c1c + smoke-test HTML + XERJ note (local, unpushed) |
| gaps/stage2 | 7a9a322a (integration); contains clippy/int (verified ancestor) -> backlog "CLIPPY merge" item is DONE, only its INT fixes remain |
| gaps/ext | 4f083d7a, EXT-E1..E4 committed, agent STILL RUNNING (uncommitted Model.pas + Parser.Delphi13.pas, lint in progress); no engine-freeze\FINGERPRINT.txt yet |
| gaps/ilc2 | 84651713, agent STILL RUNNING (fix --apply on ORM3 copy) |
| gaps/dbdoc | 2291bd58 DONE -- branched off the gaps wave, NOT main: merge into gaps/stage2 at step 2, never into main directly |
| ready for stage2 | rsv 33d198be, perf2 1f383048, chain 8d24f478, clifix 0a926ea0, prefail 635322a8, lintfix f1d85244, dbdoc; a7 cbcc87b8 LAST |
| main-only, reach stage2 via main merge | conv/startup2, conv/libdesc (+ main docs) |
| CONVERTER | conv/dlggap (incl. gateleak) still in its battery -> merge into main on READY; then items 3-6 + re-pin after re-parse (their handoff `...-converter-autonomous-lanes-until-137.md`, live session convrules-editor-31) |
| LSP | fix/lsp-clear-diags-on-close merges AFTER the release; rest is owner/IDE |
| WEBSITE | article series outline committed; release-day publish waits for go |
| docs committed | smoke test + XERJ note (db14a97a); backlog doc is gitignored by design |

Main-tree LEAK #3 (found 10:50): untracked tests\autofix\fixable-ids.txt, run_fix_fixtures.ps1, run_store_fixes.ps1,
tests\autotest\g8-common.ps1, run_dataflow_facts.ps1, run_rule_fixture_positive_control.ps1 -- copies of gaps-wave files.
At INT2: diff each against gaps/stage2, then delete from main ([IO.File]::Delete, absolute paths). Not deleted yet.

## Known-issues wave (new)
Fable triage agent (this session) re-measures every Known-issues + ENGINE Upcoming row and writes
`docs\superpowers\plans\2026-10-28-known-issues-137-plan.md` (verdicts + lane briefs gaps/ki-<x> off 7a9a322a).
y-class (extractor-hashed) fixes must merge BEFORE EXT-FREEZE or be folded into the EXT lane.

## Release split (owner 11:15, supersedes the 1.37-only reading above)
1.37.0 = the re-parse build: only y-class (extractor) items, merged before EXT-FREEZE (incl. XERJ 3/5 extraction parts if y).
1.38.0 = the PUBLISHED release: all other known issues + XERJ items 1-5 (plan docs\superpowers\plans\2026-10-28-xerj-features-137-plan.md), built in parallel lanes during the 4-5 h re-parse. Publish 1.38.0 with minimal known issues; stop early only at 98% weekly tokens.

## Next (in order)
1. Read the KI plan; dispatch FIX-NOW lanes in parallel (sonnet/haiku per brief); URGENT y-items -> EXT first.
2. Collect EXT -> merge gaps/ext into stage2 (EXT-FREEZE) -> library pre-parse into SCRATCH copies.
3. Merge rsv, perf2, chain, clifix, prefail, lintfix, ilc2, dbdoc, main, KI lanes; featuregen build --all; build.
4. gaps/a7 LAST; INT2 (review list: old handoff UPDATE 13:40 + ledger); fingerprint == freeze check.
5. Bump 1.37.0-alpha, build, featuregen verify, tell CONVERTER, deploy, swap DBs, stage install, notify owner.
Owner items: push main; plugin BPL (IDE closed, after clifix); Micronite in article screenshots?; IDE test day.

## UPDATE 17:00 -- read the ledger tail C:\TEMP\claude\lanes\gaps\LEDGER.md (10:55-17:00) first
* Freeze = gaps/ext + xj-7 + ki-exta (FREEZE-PREP lane) + ext-plat (PlatformBuiltins 8 platforms); one baseline recompute; ORM3 Win64 + libraryResolve ON; libraries first.
* 1.37.0: PREPARE release from stage3 (bump, build, pack, staged), DO NOT publish; publish only at 98% weekly tokens with 1.38 far; discard if 1.38 ships.
* 1.38 lanes (branch list in ledger): XERJ 1/3/4/5/6/8, ki-*, DEC-13/15, enumrules, dg-d0 (surface only; D1-D6 -> 1.38.1), lf-ready/marker/order, cv-migtype, ki-fp, ki-d7, D6 lab; queued RB-5 x3, lf-docs, plugin settings writer; LSP team READY: client 6e30cd5c, setup ceeb25c2.
* Plans: docs\superpowers\plans\2026-10-28-{known-issues-137,xerj-features-137,rb5-interface-dispatch-hps,two-way-modernize-downgrade,library-first-resolve}-plan.md (untracked; commit with INT2).
* Owner: 4-hourly status report (cron, session-only -- recreate after /clear); push main (9269c588) owed; IDE smoke test.
