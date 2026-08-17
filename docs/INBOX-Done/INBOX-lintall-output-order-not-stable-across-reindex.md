# INBOX -- `lint-all` output order was not stable across a reindex (FIXED 2026-08-17)

**Found:** 2026-08-17 (session 25), while verifying that the indexer-fingerprint
normalisation was content-neutral. **Fixed the same day.** Filed as Done because
it was found, diagnosed, fixed and RED-verified in one pass -- but it is worth
reading, because of WHAT it broke.

**Class:** `wrong` -- and specifically, wrong in the verification method rather
than in a rule.

## What happened

The fingerprint fix (`INBOX-indexer-fingerprint-disagrees-between-entry-points`)
forces exactly one re-parse per database. ORM3-Micronite2027 was reindexed to pay
it. Prediction, stated before the run: the engine version, schema and preprocess
platform were all unchanged -- only the RECORDED token changed -- so the index
content, and therefore `lint-all`, should be identical.

Symbol count came back **91,424, identical**. Then:

```
before reindex : 2,161,951 bytes  14,764 findings  sha 1BA0CA2D...A48A29
after  reindex : 2,161,951 bytes  14,764 findings  sha F73550AC...F57A964
```

Same size, same counts, different file. Sorted, the two reports are **identical
line for line**. 61 findings had simply moved:

| rule | moved |
|---|---|
| `high-response` | 58 |
| `low-cohesion` | 2 |
| `too-many-children` | 1 |

All three come from `TClassMetrics`, and the differing positions were one
contiguous block (13664-13724 of 14,769).

## Mechanism

`TClassMetrics.Run` emitted with `for CI in Inv.Values`. `Inv` is a
`TDictionary<Int64, TClassInfo>` keyed by **symbol id**; enumeration follows the
hash-table layout, so the order is a function of the ids. A reindex reassigns
ids, so the order moves. Nothing else in the report is keyed that way, which is
why the churn was confined to one block.

## Why it mattered more than a cosmetic reorder

**Byte-identity of `lint-all` stdout is this repo's primary verification gate.**
Every performance change in sessions 24 and 25 was accepted on it -- the
`OverloadArityTag` memo, the `seealso` memo, the `class-metrics` memo. That gate
was silently valid only *within one index state*, and nobody had written that
down. Any report-to-report diff spanning a reindex also showed churn that was not
there.

The session-25 measurements are NOT affected: every before/after pair was run
against the same index state, and each was byte-identical. What was at risk was
the next person's comparison, not the last one's.

## Fix

Sort the classes before emitting, on `(path, decl line, decl col, name)` --
source coordinates, which a reindex cannot move.
`ComputeAllFanIn` / `ComputeNOC` / `ResolveParents` also walk `Inv.Values` but
only accumulate into dictionaries or break at the first match, so their results
are order-independent and they were left alone.

## Test, and the two ways it was nearly useless

`tests\autotest\run_lintall_order_stable_across_reindex.ps1`.

1. **The first fixture used THREE files and passed against the unfixed build.**
   At that size the dictionary's enumeration order happens to equal insertion
   order, so there was nothing to detect. A `TDictionary` only diverges once the
   table has grown and rehashed. The fixture is now 30 files x (1 base + 11
   subclasses); at that size the unfixed build is demonstrably out of order.
2. **A "findings come out sorted" assertion alone would pass on any stable
   order**, including a wrong one. The suite therefore asserts BOTH: emission in
   source order (the invariant, which fails directly against the unfixed build)
   AND byte-identity of two `lint-all` runs separated by an
   `index --force-reparse` (the property that actually matters).

Verified RED against the session-24 binary -- and the RED reproduces the ORM3
signature exactly: *"29 line(s) differ; same multiset = True"*.

## Follow-up left open

The recorded ORM3 baseline SHA is now stale by design. Finding count and byte
count are unchanged (**14,764 / 2,161,951**); only the order moved, and it is now
deterministic. **The next quiet-machine run should record the new SHA** as the
baseline for future perf work.
