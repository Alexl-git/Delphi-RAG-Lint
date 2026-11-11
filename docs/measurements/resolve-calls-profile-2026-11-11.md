# resolve `calls` stage: profile and fix (151 PF, 2026-11-11)

Question (from MS-B, `ms-phase2-2026-11-10.md`): CLIENT `--resolve-only` grew x1.23
(101.4 -> 124.5 s), all of it in the `calls` stage (+23.7 s). Which part of the stage, and can
it be removed without changing a row?

## Arms (immutable copies under `C:\TEMP\claude\lanes\151\PF\arms\`)

| arm | engine | SHA256 (8) |
|---|---|---|
| A  | 150 base `_base-engine` (resolver 1.22, schema 23) -- MS-B's A | 70A9CAAB |
| B  | deployed 1.49.0-alpha (151 base engine) -- MS-B's B | 2EA90262 |
| C  | PF-BASE 2acee3297 build (ST + RB-A + RB-B) | B7334813 |
| F2 | this lane's fix (`lane/151-PF`), DRAGLINT_PROFILE_CALLS unset | 2DA701A1 |

## 1. Profile (new switch `DRAGLINT_PROFILE_CALLS=1`)

One `resolve: calls      profile:` line per binding stream of ResolveCallTargets and per hot
resolver routine (inclusive seconds, entries; a routine is timed at its outermost entry only).
Instrumented PF-BASE, 151 CLIENT copy, loaded box (CPU 21-44 %), 05:53:

| section | PF-BASE (s) | fix (s) | entries |
|---|---:|---:|---:|
| stream main (ResolveOne loop) | 56.90 | 45.96 | 1 |
| -- BindExternally | 12.19 | 1.07 | 44902 |
| -- BindExternally.DeclUses | **11.36** | 0.27 | 21015 |
| stream arg-uses (PersistArgUses) | **15.61** | 2.81 | 1 |
| stream value-reads | 15.52 | 17.12 | 1 |
| stream ref-types | 9.40 | 9.58 | 1 |
| stream writes | 8.51 | 9.35 | 1 |
| stream member-reads / parenless / ref-receivers / type-uses | 5.20 / 4.02 / 3.39 / 2.82 | 5.28 / 4.17 / 3.56 / 2.73 | |
| TypeReceiverCore | 7.49 | 7.58 | 111574 |
| calls stage total | 130.4 | 108.7 | |

The two named costs, both added in wave 150, together ~27 s (loaded) / ~24 s (idle):

* **150-RS1 (5) `4f322842b`** -- BindExternally's DeclUses called `FStore.GetUnitUsesForFile`
  (a DB read) once per library-typed receiver: 21015 reads. It runs even with no library
  attached (CLIENT `--resolve-only`: external-bound 0, no-store 44049). Fix: memo per
  declaring file (`FDeclFileUses`), read once per pass.
* **150-RS2 (2) `d98ce5bb0`** -- PersistArgUses ran one `refs` query per candidate
  (36893) filtered on `file_id, start_line, start_col, name_text COLLATE NOCASE`; `refs` has
  only `idx_refs_file` / `idx_refs_name_nocase`, so each query scanned a whole file's refs.
  Fix: candidates `ORDER BY refs.file_id`, one refs read per file into a (line, col) map, the
  same first-hit loop over the same rows in `refs.id` order. No index added (no DDL).

## 2. Identity (mandatory)

Full sorted dumps (`sql --output`, every row -- not `sql --json`) of call_edges,
member_accesses, refs (id, symbol_id, receiver_text, external_target), ref_types,
ref_receivers:

| copy | C vs fix | rows |
|---|---|---|
| 151 CLIENT copy (schema 24) | identical, all 5 | 29165 / 62988 / 297930 / 143231 / 52465 |
| 150 CLIENT copy (schema 23, ABAB final DBs) | identical, all 5 | 28229 / 62091 / 297825 / 143190 / 52458 |
| instrumented C with the switch ON vs C | identical, all 5 | (151 copy) |

Profile switch OFF: the stderr/stdout of C and F2 (ABAB runs) are identical line for line
after masking timings, clock times and pipe ids (80 = 80 lines, 0 differences); no
`profile:` line is printed.

## 3. ABAB x3 (exclusive: 0 other HEAVY lines, INT asked to hold; 2 VS Code LSP drag-lint idle)

Fresh copy of `lanes\150\_copies\client.sqlite` per run (schema 23; arm A refuses the 151
schema-24 copy), `--resolve-only`, DRAGLINT_PROFILE=1. Order A B C F2 / F2 C B A / A B C F2.

| time | round | arm | total s | calls s | CPU before / after % |
|---|---|---|---:|---:|---|
| 06:35:22 | 1 | A  | 105.9 | 88.3 | 35 / 10.5 |
| 06:37:12 | 1 | B  | 131.7 | 114.5 | 22.5 / 27 |
| 06:39:28 | 1 | C  | -- | -- | exit 3: `database disk image is malformed` at open (fresh copy); re-run as round 4 |
| 06:39:38 | 1 | F2 | 117.0 | 93.0 | 12 / 17 |
| 06:41:40 | 2 | F2 | 107.0 | 89.9 | 8 / 16.5 |
| 06:43:31 | 2 | C  | 129.6 | 113.0 | 20 / 14 |
| 06:45:45 | 2 | B  | 136.2 | 118.1 | 24.5 / 17.5 |
| 06:48:05 | 2 | A  | 107.2 | 89.8 | 6 / 16.5 |
| 06:49:57 | 3 | A  | 107.2 | 89.6 | 29.5 / 30 |
| 06:51:48 | 3 | B  | 133.8 | 116.0 | 18.5 / 10 |
| 06:54:06 | 3 | C  | 141.6 | 123.7 | 10 / 24 |
| 06:56:32 | 3 | F2 | 115.9 | 98.3 | 24.5 / 17.5 |
| 06:59:32 | 4 | C  | 134.9 | 118.1 | 22 / 8.5 |

| arm | calls mean (s) | x A | total mean (s) |
|---|---:|---:|---:|
| A  | 89.2 | 1.00 | 106.8 |
| B  | 116.2 | 1.30 | 133.9 |
| C  | 118.3 | 1.33 | 135.4 |
| F2 | 93.7 | **1.05** | 113.3 |

Fix vs PF-BASE: calls -24.6 s (-21 %). F2 / A = 1.0505 on the calls stage: at the x1.05 line.
The residual (+4.5 s) is named: PersistArgUses' remaining 2.8 s is a pass A does not run at all
(150-RS2 (2), the persisted var/out argument use: file reads + LocateArgument + one refs read per
file); the rest (~1.7 s) is inside the run-to-run spread of one arm (F2 89.9-98.3 s). Owner
decides whether the x1.05 line counts the new pass.

Final head (after the lint pass moved the per-file load into `LoadArgCalleeRows` with a try/finally; arm F3, SHA256 B4B788AE): CLIENT resolve-only 115.8 s total at CPU 31 %, all 5 tables identical to C again (151 copy). Not re-ABABed: the change is a routine extraction.

Raw: `C:\TEMP\claude\lanes\151\PF\scratch\abab.txt`, `ab-*.log`, `prof-*.log`, `id*-*.txt`.
