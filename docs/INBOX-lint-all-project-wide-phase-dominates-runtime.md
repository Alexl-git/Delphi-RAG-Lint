# INBOX -- `lint-all`'s project-wide phase dominates runtime on a large project

Found 2026-08-11 while measuring the ownership-scoping change on ORM3.
**Largely FIXED 2026-08-12** -- see "What it was" and "What is left" below.

## Status

ORM3-Micronite2027 `lint-all` **now completes in 732 s (12.2 min)**. Before, it
burned **8,705 CPU-seconds (2.4 h) and had not finished** when it was killed.
Findings are unchanged: the same 19,024, byte-identical report.

| phase | before | after |
|---|---|---|
| per-file scan (565 files) | 151.6 s | 151.6 s |
| **project-rules** | **did not finish** | **30.4 s** |
| doc-drift | 433.0 s | 454.9 s |
| class-metrics | 61.4 s | 60.9 s |
| duplicate-code | 10.2 s | 10.1 s |
| finalize+output | 21.2 s | 18.9 s |
| **TOTAL** | never completed | **732.3 s** |

YADF (8 files) went 77.8 s -> 34.6 s over the same changes, report identical.

## How it was found -- measure, do not guess

The note's own advice held. `lint-all` had no per-phase timing, so the first
change was to add one: **`DRAGLINT_PROFILE=1` now gives `lint-all` a per-phase
breakdown on stderr**, matching the indexer's. It announces each phase when it
OPENS and prints the cost when it CLOSES, streaming, precisely so that a run
that never terminates still names the phase it died in -- an end-of-run report
would have printed nothing at all for the case being diagnosed.

That pinned it to `project-rules`. Attributing it further needed no new code:
**`lint-project --rule <id>` already runs exactly one project rule**, so timing
one run per rule id gives per-rule cost. On YADF that produced the whole answer
in 40 seconds:

```
zzz-baseline-none                  0.52 s     god-class                0.57 s
circular-uses                      0.23 s     unused-public-symbol     0.33 s
enum-helper-separate-units         0.22 s     unused-private-member    1.26 s
repeated-type-switch               0.39 s     unused-unit-in-uses     32.21 s   <--
```

A per-rule breakdown is now built in too (same `DRAGLINT_PROFILE`), because the
ORM3 ranking turned out NOT to match YADF's and one run beats eight.

## What it was -- three rules, one shape

Every one of them asked the store a question **per occurrence** that it could
have asked **once per run**.

**1. `unused-unit-in-uses`** -- 32.2 s of YADF's 37.4 s pass; unbounded on ORM3.
For every reference in every file it called `FindSymbolsByExactName(Ref.NameText)`
plus a `GetFilePath` per matching symbol, i.e. O(all refs in the index) queries,
repeated per file. Identifiers recur constantly (`Create`, `Result`, `Free`), so
almost all of it was recomputation. Fixed with a run-level memo of name -> unit
stems, keyed on the raw name so a memo hit answers exactly what the query would.

**2. `unused-private-member` (447.8 s on ORM3) and 3. `unused-public-symbol`
(59.0 s)** -- both tested "is this symbol referenced at all?" as

```pascal
(Length(AStore.FindReferencesTo(Sym.Id)) = 0) and (Length(AStore.FindCallersByName(Sym.Name)) = 0)
```

Two queries per symbol, each MATERIALISING EVERY MATCHING ROW into a TReference
just to compare a length with zero -- and `refs.name_text` carries **no index**
(`FindCallersByName` says so in its own comment), so the second was a **full
table scan per symbol**. Replaced by two new store methods,
`GetReferencedSymbolIds` and `GetReferencedNamesLower`, one DISTINCT scan each,
loaded into sets once per run. The name set is lowercased because the query it
replaces matched `COLLATE NOCASE`, and that collation and Delphi's `LowerCase`
both fold ASCII only, so the two accept the same rows.

Result: `unused-private-member` 447.8 -> **0.01 s**, `unused-public-symbol`
59.0 -> **0.36 s**, `unused-unit-in-uses` unbounded -> **17.4 s**.

## What is left

1. **`doc-drift` is now the dominant phase: 454.9 s of 732.3 s on ORM3**, and
   21.6 s of YADF's 34.6 s -- it was simply invisible behind project-rules
   before. Not yet investigated. It is also the subject of
   `docs\INBOX-autodoc-not-idempotent-on-yadf.md`, so the two are worth looking
   at together.
2. **`unused-unit-in-uses` is still 17.4 s** -- the memo removed the repetition
   but the remaining cost is one `FindSymbolsByExactName` per DISTINCT name,
   each an indexed lookup returning every symbol with that name.
3. **`refs.name_text` has no index.** `find-callers` is the index's headline
   query and it is a full table scan on every call. The lint path no longer
   cares, but every interactive caller still pays it. Adding the index is a
   schema migration and was deliberately left out of this change.
4. The pre-existing quadratic `Findings := Findings + <rule results>`
   accumulation in `DoLintAll` was NOT touched. It never showed up: the
   ownership filter over all 54,245 raw findings costs 0.03 s.

## Reproducing

```
set DRAGLINT_PROFILE=1
cd C:\Projects\Delphi-RAG-lint\third_party\dll-win64
drag-lint lint-all --db C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite --quiet
```

Read **stderr**: the profile and the status lines are unbuffered there, whereas
stdout is block-buffered when redirected and shows nothing until the process exits.
