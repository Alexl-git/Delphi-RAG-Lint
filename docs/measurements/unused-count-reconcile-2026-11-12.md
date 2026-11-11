# unused-global / unused-public-symbol: MS-B 339 / 390 vs UG 241 / 288 (wave 152, lane MS)

STATUS: DONE (MEASURED 2026-11-11, one copy, base engine 1.50.0-alpha). The command lines do NOT explain the gap.

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

## Phase 1 result (MEASURED)
One copy of _copies\client.sqlite (656 files), the 1.50.0-alpha engine, `lint-all --json`, ids = rule|file|start_line|message:
| run | command | total | unused-global + unused-public-symbol |
|---|---|---|---|
| B1 | --rule unused-global,unused-public-symbol (UG) | 529 | 241 + 288 |
| B2 | same again (positive control) | 529 | identical |
| A1 | --enable <the 15-rule MS-B list> | 23443 | identical to B1 |
B1 vs B2: 0 / 0. B1 vs A1: only-in-B1 0, only-in-A1 0. So `--rule` vs `--enable` reconcile to 0 unexplained findings
and the 339 / 390 of MS-B is NOT produced by its command line on this copy: the copy gives 241 / 288 with either.
## Cause of the 339 / 390 vs 241 / 288 gap
By elimination the difference is the index state MS-B ran on: its DB (old schema-23 copy / real DB before the 09:07 re-parse)
and the sibling projects' DBs at that moment (SHARED-UNIT-SCOPE 3a2ee6028 judges a shared unit by every sibling that lists it;
an undecided sibling is silent). The current copy (656 files) is a post-re-parse index. NOT proven per finding: the 98 + 102
extra findings of MS-B were not re-derived (that index no longer exists); the 241 / 288 set is the current truth.
Total 23443 on the copy vs MS-B 23561: unrelated index drift, not analysed.
