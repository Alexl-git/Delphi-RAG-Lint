# Resolve calls stage -- profile below stage level and A/B (152 PF2, 2026-11-11)

Rows closed: leftovers s1 "resolve x1.23 (101.4 to 124.5 s), all in the calls stage" (151 PARTIAL x1.0505 vs x1.05) and
s4 "resolve x1.23 profile below stage level". Predecessor: resolve-calls-profile-2026-11-11.md (151 PF, which made the fix).

## Setup
- Engines (immutable copies, C:\TEMP\claude\lanes\152\PF2\arms\): A = 151 PF arm A (`--version` 1.49.0-alpha build, resolver 1.22,
  sha256 70A9CAABBBD41648...), B = 152 base = deployed 1.50.0-alpha (resolver 1.24.0-alpha, sha256 4B251F3A11093B40...).
- Script: C:\TEMP\claude\lanes\152\PF2\run-pf2.ps1 (self-gating on `BOX IDLE` + 0 open HEAVY lines; fresh DB copy per run with
  a files-count check; a run without a `stage: calls -- done in` value is recorded FAIL, never carried over).
- Command per run: `drag-lint index --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --db <fresh copy> --resolve-only`,
  DRAGLINT_PROFILE=1.
- Box: exclusive slot (ledger HEAVY-START/END 17:34:44 - 17:48:14), 3-4 other drag-lint processes alive (IDE/LSP, idle),
  CPU 10-30 % before / after each run.

## Profile (B, DRAGLINT_PROFILE_CALLS=1, 152 CLIENT copy, schema 25, 656 files, 17:34:45)
total 115.3 s, calls stage 97.8 s (switch ON). Every one of the 24 sections present with > 0 entries
(tests\autotest\run_profile_calls_identity.ps1 -ProfileLog: T1 PASS). Sections over 1 s:

| section | s | entries |
|---|---:|---:|
| stream main | 40.69 | 1 |
| stream value-reads | 15.76 | 1 |
| stream ref-types | 8.77 | 1 |
| stream writes | 7.86 | 1 |
| TypeReceiverCore (inside the streams) | 6.76 | 113021 |
| stream member-reads | 4.66 | 1 |
| stream parenless | 3.51 | 1 |
| stream ref-receivers | 3.16 | 1 |
| stream type-uses | 2.71 | 1 |
| stream arg-uses | 2.50 | 1 |
| LookupTypeName (inside the streams) | 2.11 | 21506 |
| LocalInScopeAt (inside the streams) | 1.29 | 106167 |

Below 1 s: BindExternally 0.98 (45853), LinesOf 0.76, enum-values 0.61, FileUsesUnits 0.29, enum-casts 0.28,
BindExternally.DeclUses 0.26 (21450; 151 fix holds: was 11.36 s), type-reads 0.21, ResolveTypeNameToSymbol 0.19,
exception-types 0.12, TypeOfSelectorChain 0.12, DecideInlineInitType 0.01, InlineInitMemberType 0.00.
Routine rows are nested inside stream rows: do not add them to the stream total.

## ABAB x3 (A / B alternating, order reversed on round 2; 150 CLIENT copy, schema 23, 652 files -- the only CLIENT copy arm A opens)

| start | round | arm | total s | calls s |
|---|---|---|---:|---:|
| 17:36:45 | 1 | A | 115.2 | 97.2 |
| 17:38:45 | 1 | B | 113.0 | 96.7 |
| 17:40:42 | 2 | B | 115.7 | 98.4 |
| 17:42:43 | 2 | A | 105.3 | 88.5 |
| 17:44:33 | 3 | A | 106.5 | 89.6 |
| 17:46:24 | 3 | B | 107.7 | 91.8 |

calls stage mean: A 91.77 s, B 95.63 s -> **B/A = 1.042** (151 PF measured 1.0505 for its fix arm). Per-round B/A:
0.995, 1.112, 1.025 -- the spread of one arm (A 88.5-97.2) is larger than the A/B gap.

## Result
calls stage <= x1.05 of A: **DONE** (s1 closes; s4 closes with the table above). Residual +3.9 s is inside one arm's spread;
the only pass A does not run is `stream arg-uses` (2.50 s, the 150-RS2 feature). No phase-2 code: the close criterion is met,
and no single sub-pass over 2 s is a removable cost -- each is a stream doing its own resolve work (O1 ruling: accept residual).
