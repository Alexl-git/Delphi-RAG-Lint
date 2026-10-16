# Index speed at any cost, and one `explore` entry point for agents

Status: branch `perf-explore`. Front 1 reached its target on 2026-10-14 (P1, P2 and the fixed-cost
work below); P3, P4 and front 2 not started. Rulings by the project owner on
2026-10-14. This document records WHAT was decided and WHY; the CHANGELOG `Unreleased` section
has the per-change detail and measurements, and the commit messages the implementation notes.

## Why

On 2026-10-14 the owner observed that, on real Delphi projects, an LLM agent gets more out of a
ripgrep-based MCP server than out of drag-lint -- which would make the project pointless. Two
causes were measured the same day:

1. **The index cannot keep up with editing.** A one-file incremental took 70-80 s on the daily
   project and 47.7 s on the test closure; ten changed files took 455 s. An agent that edits and
   then queries gets stale answers or waits.
2. **The answers are not shaped for an agent.** Output is cp1252 (also inside `--json`), most
   verbs return locations without code, several outputs have no size bound, there are ~60 verbs
   with different name forms, and the MCP server has defects (Gitea drag-lint#31-#39). The ripgrep
   server wins because every answer already carries the decoded code. CodeGraph reached the same
   conclusion and converged on ONE tool, `explore`, that returns the verbatim source of the
   relevant routines, the call path among the named symbols and the blast radius, capped at ~24K
   characters (their measurement: 88% fewer tool calls, 53% less time, no file reads).

## Rulings

| # | Question | Ruling |
|---|---|---|
| R1 | Target for a one-file incremental? | **Under 10 s.** |
| R2 | May the schema and the pipeline change? | **Yes**, including an extractor bump and a full re-parse of every index. |
| R3 | What must not break? | The upstream author's verbs and flags keep working (same rule as E3b). |
| R4 | Where is speed measured? | Only on the test repositories, with `tools\perf\scenarios.ps1`; a speed change is accepted only when `tools\measure\index_db_diff.py` reports IDENTICAL against the previous exe, unless the difference is intended and explained. |
| R5 | How is agent usefulness judged? | By an A/B of real agent tasks (ripgrep only / ripgrep + drag-lint / ripgrep + `explore`), not by taste. The owner's scenario: everything around `UConfig.pas` -- the document-configurator structure (`TConfigTab`, `TConfigTabs`, `TConfigCol`, `TConfigCols`, ...). |

## Outcome of front 1 (2026-10-14)

Measured with `tools\perf\scenarios.ps1` on the TestCopy ProjectA closure (2,218 files), Release,
against the exe deployed that morning; every database IDENTICAL by `tools\measure\index_db_diff.py`:

| Scenario | Before | After |
|---|---|---|
| nothing changed | 8.9 s | 3.7 s |
| one large form changed (`UFEditA.pas`) | 72 s | 9.9 s |
| one small form changed | -- | 8.5-9.8 s |
| ten forms changed | 421 s | 50-66 s |

What it took, in the order the profile pointed at: FTS5 patched from a receipt instead of live
triggers; params/locals out of the call scope; symbol ids kept across a re-parse (P2); the `files`
lookups on an expression index instead of an `OR` that scanned the table per lookup; the call scope
evaluated once; the scoped purity pass reading only its scope; the compile-closure scan cached; and
a write-time + size fast path in the walk. The `DRAGLINT_PROFILE` phase timers (`INDEX PHASES`,
`INDEX WALK`) are what found the last four. `DRAGLINT_RESOLVER_VERSION` moved to 1.21.0-alpha.

Two measuring lessons, recorded because they cost hours: identical runs vary by ~5 s on the
measuring machine; and the first checkpoint into a freshly copied 500 MB database stalls ~20 s (an
OS/antivirus effect), so a benchmark must write to its copy once before the clock starts.

## Order

1. **P1 -- no extraction change.** Done: params and locals out of the scoped call pass, FTS5
   patched from a receipt instead of live triggers, purity reads classes and heritage once.
2. **P2 -- stable symbol ids.** Done, and without an extractor bump: extraction is unchanged, only
   the store keeps rows. A re-parse updates unchanged declarations in
   place instead of delete-and-reinsert, so edges into the file survive and a body edit re-resolves
   only its own file.
3. **P3 -- parallel full index** (same bump): a pipeline of parse workers and one writer, facts
   out of the per-file transaction, bulk writes, a parallel call pass.
4. **P4 -- an index that stays fresh**: an incremental run after each edit, and per-file stale
   banners at query time.
5. **Front 2**: UTF-8 output and the MCP fixes, then an `explore` verb and MCP tool after
   CodeGraph's design (seeds by name, segments, signatures, docs and string literals; expansion
   over resolved call edges, heritage, uses and DFM handlers; per-file ranking with a random walk;
   verbatim, line-numbered routine bodies within a budget), then the A/B again.
