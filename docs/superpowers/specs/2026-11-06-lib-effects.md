# E-BIND-LIB-EFFECTS: follow calls into the library for effect summaries

Status: designed and measured, NOT in the code. It would need a resolver bump, and the measurement says it
is not the lever the backlog row hoped for. Recommendation: do not spend a bump on it. Lane g1, wave 146,
2026-11-06. The exact change is in `2026-11-06-lib-effects-next-bump.patch` beside this file, should the owner
want it anyway.

## 1. The problem

The purity stage (`DRagLint.Analysis.PurityStage`) writes `effect_free` / `effect_summary` per routine at
resolve time. A call with no local `call_edges` row is an unbound `?`, also when the resolver knows the target
by name (`refs.external_target`, e.g. `System.Generics.Collections.TDictionary.Add`). Six rules read those
verdicts:

| Rule | Needs |
|---|---|
| `assert-with-side-effect` | a proven effect (g, h, s, p<k>) |
| `side-effect-in-short-circuit` | a proven effect |
| `query-name-with-effect` | a proven effect |
| `property-getter-with-effect` | a proven s or g |
| `discarded-effect-free-result` | proven effect-free |
| `effect-free-in-loop-invariant` | proven effect-free |

The row's claim: following those calls into the library's own verdicts is "the real lever" for all six.

## 2. Options

A. **At resolve time, in the fixpoint (chosen for the measurement).** `CallRef` takes the library summary for a
   call with a stored `external_target`, through the existing built-in path of the fixpoint
   (`TranslateCallee` already moves `s` through the receiver and `p<k>` through the lexed arguments). About 120
   lines. Verdicts are stored, so all six rules, hover and the doc facts see them.

B. **At lint time, an overlay in the rules.** No resolver change and no bump, but `?` is one flag with many
   causes and only the first witness is stored, so an overlay can only add flags, never remove `?`, and it
   cannot carry an effect transitively without re-running the fixpoint (minutes per lint).

C. **Copy the library's verdicts into the project DB as stub symbols.** Purity recomputes every routine from
   its body, so a stub reads as empty, hence effect-free: unsound without changing the stage anyway.

D. **Make the library's verdicts good first.** See section 6. A library re-parse with usage refs.

A is the only one that can answer the question at the row's scope, so A was built and measured.

## 3. Rules of the design

* OFF by default. `DRAGLINT_LIBRARY_EFFECTS=<library.sqlite>` turns it on for one run; there is no CLI surface.
* A virtual or interface member stays `?`: the override is not the body we can see (same rule as `BoundCall`).
* Overloads under one qualified name join (flags and params union).
* **Every library summary keeps `?`.** The library is parsed shallow (`EmitUsageRefs` off for a library
  section), so its bodies carry no read or write refs and its `effect_free = 1` proves nothing:
  `Data.DB.TDataSet.Open`, whose body is `Active := True`, is stored effect-free with one `type_use` ref. A
  project routine therefore never becomes effect-free because of a library callee.
* **`h` is not taken from the library** (section 5). `DRAGLINT_LIBRARY_EFFECTS_TRUST=1` is the unsound
  measurement arm: it takes verdicts at face value, `h` and `effect_free = 1` included.

## 4. Why it needs a bump

`DRagLint.Analysis.PurityStage.pas` is hashed whole on the resolver surface (`tests\resolver-surface.txt`), so
any edit reds `run_resolver_version_guard.ps1`, even one that changes nothing while OFF. Reading the target
also goes through `GetUnresolvedCallsFromSymbol`, because `GetReferencesFromFile` drops `external_target`.

## 5. Measurement

Lane-private copies of two DBs, `index --project .. --resolve-only --library-db library-Win64.sqlite`, then
`lint-all --db <copy> --library-db <lib> --rule <id> --json`, counted on the `rule` field. Library: Win64,
extractor 1.31 (the engine is 1.32; the library was "NOT READY -- stale-extractor", used anyway as named).

OFF proof: Micronite2027 with the unpatched engine against the patched engine with the switch unset:
`symbol_facts` (11,099 rows: id, effect_free, summary, witness) byte-identical.

| Rule | Micronite2027: off / with h / shipped design / trust | drag-lint: off / with h / shipped design / trust |
|---|---|---|
| assert-with-side-effect | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| side-effect-in-short-circuit | 1 / 5 / 1 / 5 | 133 / 325 / 215 / 325 |
| query-name-with-effect | 1 / 1 / 1 / 1 | 21 / 56 / 32 / 56 |
| property-getter-with-effect | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| discarded-effect-free-result | 3 / 3 / 3 / 3 | 0 / 0 / 0 / 0 |
| effect-free-in-loop-invariant | 0 / 0 / 0 / 0 | 3 / 3 / 3 / 4 |
| routines proven effect-free | 2,911 / 2,911 / 2,911 / 2,914 | 558 / 558 / 558 / 692 |
| library summaries taken (call refs) | 0 / 8,252 / 8,252 / 8,252 | 0 / 21,826 / 21,826 / 21,826 |

"with h" means taking the library's `h`. All four new Micronite findings there, and the samples read on
drag-lint, came from a library routine freeing its own temporaries (`IsCweId` "calls IsMatch (frees storage)",
`CharHasData`), so `h` was dropped.

Quality of what remains: 20 new findings sampled across the drag-lint list (9 short-circuit, 11 query-name),
read from the line and the witness, not a full triage. None reads as a bug; they are memo caches
(`SymbolById`, `TypeIs`, `ProjectHasRoutine` adding to a `TDictionary` field) and routines already flagged for
another reason. `effect-free-in-loop-invariant`'s +1 in the trust arm rests on the unsound verdicts.

Resolve time: no visible cost; a run took 266-346 s (Micronite) and 379-466 s (drag-lint) on a saturated
machine with every arm inside that noise.

Why so little: where 11,236 stored library-bound calls in Micronite2027 land, by target's verdict:

| Library verdict | Targets | Calls | Share |
|---|---|---|---|
| `?` only | 165 | 6,402 | 57% |
| virtual / interface | 124 | 2,237 | 20% |
| some proven effect | 115 | 1,766 | 16% |
| "effect-free" (not trustworthy) | 37 | 588 | 5% |
| no verdict (external declarations) | 85 | 243 | 2% |

So the library mostly answers `?` itself (`Format` because `FmtStr` is unbound, `FieldByName` because
`FindField` is, `Free` because `Destroy` is virtual).

## 6. Recommendation and what the owner can reverse

* **Do not take the patch.** On the owner's own application the shipped design changes no rule count; on this
  repo it adds 93 findings that do not read as bugs. Two of the six rules (the effect-free ones) cannot gain
  from it at all while the library is shallow.
* The lever, if there is one, is the library's verdicts: option D, usage refs in the library parse (a re-parse
  of the library DBs, which grow; size unmeasured), and only then this patch. Not estimated here.
* A curated axiom list for the commonest `?`-only targets (`Format`, `FieldByName`, `IntToStr`, `Trim`) would
  move the effect-free rules more cheaply and soundly than either. It also edits `Analysis.Purity`: a bump.
* Reversible assumptions: `h` dropped; `?` always kept; virtual stays `?`; one library per run; env switch
  rather than a flag. Each is a line in the patch.
