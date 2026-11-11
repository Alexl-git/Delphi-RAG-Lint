# Hover cost, wave 151 CF (LX-5) -- 2026-11-11

Tool: tests\autotest\tools\hover-cost.ps1 (151 CF adds -RequireIdentical: per hover id, A's markdown vs
B's, ordinal; a difference fails the run). ms per hover = (T_N - T_1) / (N - 1), min over repeats.
A = base engine 1.49.0-alpha (lanes\151\CF\engine, the 151 BASE BUILD), B = lane/151-CF wt build.
Read-only copies in lanes\151\CF\scratch. Shared machine (9 CPUs, ~10 agents): the same engine ranged
60-125 ms/hover on the same CLIENT sample between runs, so only same-run A/B pairs are compared.

## Where the time went (base, 100 hovers, temporary stopwatch instrumentation, not committed)
CLIENT copy (99 undocumented + 1 documented hover, 8 files):
- IdentifierAtPosition: a full tree-sitter parse per hover, 905 ms.
- TTypeAtResolver.Resolve: 135 calls for 100 hovers (SelectSymbolAt and the undocumented branch asked the
  same question); inside it GuiFrameworkInUse (GROUP BY over unit_uses, uncached) 1,078 ms.
- ExceptionFactLines: TChartsIndex.Create (a store open) per hover, ~9 ms each.
- TDocFactsBuilder.Build 3.5-4.1 s, of which covered-by (Doc.SymbolFacts.ComputeCoveredBy) 1.1-2.25 s.
drag-lint DB copy, src\query routines (38 documented):
- Build 6.2 s: unresolved-name window 4.45 s = OverloadArityTag 2.38 s (1,637 calls, sibling materialisation
  per caller row) + ForeignReceiverType 2.44 s (1,340 calls, 1,065 distinct (routine, receiver)); covered-by 1.74 s.

## Fixes (each identity-preserving: same queries on a miss, same answer)
| commit | change |
|---|---|
| 43a4013e0 | IdentTreeFor: last parse tree reused when path + PREPROCESSED bytes match; TSymbolSelection carries the TypeAt answer to the undocumented branch; TypeAt asks GuiFrameworkInUse only at its one consumer |
| bd50aa97d | ExceptionFactsOfIndex over a kept-open TChartsIndex (dropped on re-index, in Destroy) |
| bcde399ff | OverloadArityTag: per-(store, parent) routine name counts |
| 76075750a | C14 receivers: ScopeMember memo per (store, scope, name); known-foreign verdict memo per (store, file, type, owner) |
| 9a17bc182 | found-in-151: ClearDocFactsMemos before the LSP opens any store (pointer-keyed memos vs freed/reopened stores) |

## Results (100 hovers, 100/100 answered, IDENTITY OK 100/100 in every row)
| sample | repeats | A base ms/hover | B wt ms/hover | after commit |
|---|---|---|---|---|
| CLIENT copy | 3 | 60.7 | 48.4 | 43a4013e0 |
| CLIENT copy | 3 | 59.4 | 43.8 | bd50aa97d |
| CLIENT copy | 3 | 56.3 | 39.3 | bcde399ff |
| drag-lint DB, src\query (documented) | 3 | 131.4 | 89.8 | bcde399ff |
| CLIENT copy | 3 | 70.6 | 49.0 | 76075750a |
| drag-lint DB, src\query | 3 | 149.2 | 95.6 | 76075750a |
| drag-lint DB, src\lsp (1 file, 145 KB md) | 3 | 252.1 | 141.6 | 76075750a |

Net: about 30-44 percent less per hover, byte-identical answers.
Positive control of -RequireIdentical: A = B = base, -ExtraB --no-exception-facts -> IDENTITY FAIL 2/100, exit 1.

## Left
- covered-by (ComputeCoveredBy, Doc.SymbolFacts, X2R's file in 151): 11-18 ms per hover; a reverse walk of up
  to 200 callers with two caller queries each. Not touched here (FOUND-151 to X2R / INT).
- Remaining Build sections each 1-4 ms; StoresForFile ~2.5 ms (context resolution per hover).
- Limit: the samples hover routine names on their declaring lines; call-site hovers take the TypeAt path more.