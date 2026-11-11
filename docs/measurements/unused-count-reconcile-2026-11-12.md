# unused-global / unused-public-symbol: MS-B 339 / 390 vs UG 241 / 288 (wave 152, lane MS)

STATUS: Phase 0 (command diff) DONE; Phase 1 (the two runs on one copy, set difference) NOT RUN: it needs a HEAVY slot
(CLIENT lint-all, 16-30 min) and the box was BUSY (ORM3), no `CTRL COPIES READY`. FINISHER: staged\ms-phase1.ps1.
The cause below is therefore a HYPOTHESIS, not a result.

## Phase 0: the two commands, flag by flag
| | MS-B (ms-phase2-2026-11-10.md s1) | UG (lanes\150\UG\REPORT.md) |
|---|---|---|
| verb | lint-all --json | lint-all --json |
| DB | `client.sqlite` (the _copies\ schema-23 copy for the count 340/390; "REAL CLIENT DB" gives 339 for unused-global) | the REAL CLIENT DB, re-parsed 09:07 that day |
| rule selection | `--enable <15 ids>` = the DEFAULT set PLUS 15 (all default-on rules run) | `--rule unused-global,unused-public-symbol` = ONLY those two |
| sibling project DBs | as at run time (ORM3 re-indexing in parallel) | as at run time, ~30 min under load |
| engine | deployed 1.49 AND 150 base | deployed |
Differences: (a) `--enable` vs `--rule`, (b) copy vs real DB, (c) wall-clock moment, i.e. the state of the sibling DBs
that SHARED-UNIT-SCOPE (3a2ee6028) consults: an undecided sibling scope is SILENT, a decided one reports. 339 -> 241 is
fewer findings under the UG command, which fits "more siblings undecided/stale at that moment" or "a sibling scope that
references the symbol", not a rule difference (the --rule/--enable parity sweep: 41/41 identical, ms-phase2 s9).
## Phase 1 plan (acceptance)
B1 (UG command), B2 (same, positive control: identical sets), A1 (MS-B command) on ONE copy; ids = rule|file|start_line|message;
report B1\B2 = 0, and A1\B1 / B1\A1 classified (unit, section tier, message). Accept: 0 unexplained.
Measured so far: nothing beyond Phase 0.
