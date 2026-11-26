# Fields that need data of other tables -- goals first (DRAFT for the owner, 2026-11-25)

Status: DRAFT. Nothing decided or built. Owner: "approach this from the point of what we need to achieve, and then
we'll know what we need for it"; "IPCHART here is just an example. We need to consider a generic situation."
Affects Q4 (A given), Q5, Q6, Q18, Q24 and ruling R3 (`{{TABLE.FIELD}}` is an error today).

## 1. The generic situation

A CONSUMER on a form, whose rows belong to a HOME table, needs INPUTS that are columns of other tables.

* Consumer: calculated field, lookup, OnGetText, grid display text, cell drawing, OnValidate / OnChange.
* Home: whatever the dataset's rows are: a table, a join, a memory table.
* Input: a column of the home table, of a parent (N steps up the foreign keys), or of something that is no parent.

Example: IPCHART (home), FTRNAME and the number format (consumers), MSCLIST.DECIMALS (input, 2 or 3 steps up).

## 2. What we want to achieve

| # | Goal | Done when |
|---|---|---|
| G1 | Pick any stored consumer for any dataset where its inputs can be reached; it shows the right value | Same value as the M2022 form for the same rows |
| G2 | DL finds what is missing (columns, joins, rows), shows it, adds it after a yes | One dialog, every addition unticked-able |
| G3 | One formula stored once, usable from several home tables | One fix reaches every form |
| G4 | Do not read again what the form already holds, if it is the right data | No query when the rows are there; only missing rows are fetched |
| G5 | Works without SQL to extend (CLIENT memory tables) | Same consumer on a TFDMemTable |
| G6 | Never a wrong value silently | Unknown input or row = empty and reported |

## 3. Measured (read-only, 2026-11-25)

Foreign keys of the local MICRONITEV6A (297 over 139 tables, 72 tables declare none):

| Steps up, at most | Table pairs reachable | More than one path |
|---|---|---|
| 1 | 274 | 11 (4%; one of them is a two-column key, so 10 real ones) |
| 2 | 1,089 | 334 (31%) |
| 3 | 1,653 | 1,168 (71%) |

(Rows 2 and 3 count that two-column key twice as well, so they are slightly high.)
So with 3 steps a path must be chosen, not guessed. (Some paths are roles: FOLDERS has 7 foreign keys to OPTRLIST.)
Two paths may still mean the same row: IPCHART to MSCLIST through INSPRSLT.FTRID or through IINSP.CHARID agrees on all
2,232,615 rows of this database. That is today's data, not a guarantee.

M2022 join forms that carry calc or lookup fields (59 datasets; own quick parser, SQL of the DFM only; 151 join conditions):

| Join condition | Count |
|---|---|
| along a declared foreign key | 107 |
| to a key column, but no foreign key declared (16 to TOOLGR12, 1 to MACHPOS) | 17 |
| other (16 of 17: TOOLASSG with TOOLFLDR, four columns) | 17 |
| not resolved by the parser | 10 |

35 of the 59 datasets join only along declared foreign keys.
Formulas: 68 calc field names occur more than once (593 fields); 51 names use the same tables everywhere, 17 do not
(judged by name, not by comparing code). 70 of 830 calc fields with code read several known tables.

## 4. What the goals need

| # | Need | Serves | Generic rule |
|---|---|---|---|
| N1 | Origin of every field: table, column, path, or "computed / unknown" | all | Survey steps 1-4 (Q4 A). Per field, not per dataset |
| N2 | Relation list: foreign keys + relations found in the forms' joins + hand-added | G1, G2 | Usable only if the parent side is unique (primary key or unique index), so a join never multiplies rows. A found relation is offered, not assumed |
| N3 | Path stored as a NAMED role ("OPERAT via COPERATOR"), not only a table name | G1, G6 | Several paths: take the one of the form being read; otherwise ask |
| N4 | FORMULA with named inputs, stored once; BINDING per home table says where each input comes from | G3 | Answers Q5. Home table MSCLIST: all inputs local; home table IPCHART: limits local, the rest through the role |
| N5 | Delivery, chosen per form: JOIN (extend the SQL), KEYED (find the parent row in a loaded table), SNAPSHOT (compute while loading) | G2, G4, G5 | Same formula and binding in all three |
| N6 | Proof that loaded rows are the right ones | G4, G6 | See 5 |
| N7 | Dependency closure: a consumer that uses another calc field brings that field's inputs too | G2 | Exists for one table (rule S1 of the v2 design); extend over roles |

Consumers that need no other table stay exactly as today.

## 5. "Do we hold the right chunk?" -- generic answer

Going up a unique key, nobody has to know HOW the loaded table was filled. Check the keys:
every key value the home rows ask for must be present in the loaded parent table. Rows of other parents do no harm,
they just do not match. Missing keys: fetch exactly those, or leave empty.
A loaded table may be used only if also:
1. it has the needed columns;
2. those columns are unchanged copies of the base table (N1), not recomputed;
3. the same thread owns it (TFDMemTable is not thread-safe), or it is an immutable buffer (the ORM3 flat-read draft);
4. its age is acceptable (P2).
Over several steps the check is repeated per step, or the keys are carried in one extra column of the home rows.
Not covered by this: going DOWN (one to many: sums, counts, last sample). That needs an aggregate query; the survey found 3 such fields.

## 6. Order (each step is useful alone)

1. N1 for joins (survey step 1: +258 calc, +179 lookup).
2. N2 + N3: relation list and roles in the repository. 3. N4: formulas and bindings, filled by reading M2022.
4. Dialog "also needs ..." with JOIN. 5. Survey steps 2-4 (memory tables). 6. KEYED with the key check, after ORM3's flat-read design is settled.

## 7. Open for the owner

* P1 Several paths and no old form decides: ask every time (A), or ask once and store it as the default role (B)? Recommendation: B.
* P2 May a loaded parent row be older than another user's last save? Yes, until the form refreshes (A); re-read (B). Recommendation: A.
* P3 The same formula with inputs from different tables (IPTrack uses the sample's limits, most forms the characteristic's):
  keep both bindings (A), or treat as two formulas (B)? Recommendation: A.
* P4 "Another situation that probably will happen often on CLIENT is we have TFDMemTable ...": the sentence stopped there.

## 8. Not known

* How many CLIENT (ORM3) forms hold a child and its parent at once: not counted.
* Whether M2022 joins fit foreign keys of other databases; 24 joins get their SQL at run time (not followed).
* Unique indexes behind the 34 conditions without a foreign key: not checked.

## 9. Owner answers 2026-11-26

* New goal G7: FireDAC Local SQL (TFDLocalSQL) over the tables a form already holds may extract or combine the needed columns.
  Consequence: the SQL composer (10) writes two dialects, Firebird for the server and Local SQL (SQLite) over memory tables.
  Local SQL is a fourth delivery beside JOIN, KEYED and SNAPSHOT (N5).
* New goal G8 (from P2): CLIENT data is refreshed when SERVER signals a change; SERVER reads fresh rows from Firebird itself.
  So P2 is not a DL policy: KEYED and Local SQL reuse loaded rows, and the existing change signal invalidates them by key.
* P1 = B: ask once, store the answer as the default role of that relation.
* P3 = A: ONE formula per field. A binding is not a second formula: it only says which table feeds each named input.
  CLIENT never chooses between formulas. (IPTrack's use of the sample's limits becomes a binding of the same formula.)
* P4: dropped for now (owner).

## 10. Can DL compose the join SQL from the schema? (owner question 2026-11-26)

Yes for the common case, as a mechanical step once the inputs and roles are known:
home table + needed columns + one role per parent -> one LEFT JOIN per step along a unique key, one alias per role,
the needed columns added to the select list, the form's own WHERE / ORDER BY kept. LEFT keeps every home row when a key is NULL;
a unique parent key guarantees the row count does not change. Both are checkable from the schema.

It cannot decide alone, and asks or refuses:
* several paths and no stored role (P1 B: ask once);
* a relation that is no declared foreign key (34 of 151 M2022 conditions): offered for confirmation once, then stored;
* a parent side with no primary key or unique index: refused (rows would multiply);
* going DOWN (sums, counts, latest sample): needs an aggregate subquery; offered as a separate kind, not a join;
* SQL built at run time (24 M2022 joins): not rewritten.

Proof before it is written into a form: prepare the statement against the database (syntax, names, types), then run it next to
the form's current SQL with a row limit and compare the row count and the values of the columns both return. A mismatch refuses the change.
