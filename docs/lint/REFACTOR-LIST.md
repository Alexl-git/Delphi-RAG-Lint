# drag-lint -- Refactoring-APPLY roadmap & progress

The **apply** frontier: transformations drag-lint can *perform* on source (not just
*detect*). Detection coverage is effectively complete (see `MISSING-FEATURES.md`);
this file tracks the actionable refactorings and our progress on them.

Scope of "done" here = **correct + complete + IDE-integrated** (invoked from the
editor, previews changes, applies, reloads), not merely a CLI proof-of-concept.

## Legend

- `[x]` shipped &middot; `[~]` in progress (current deployment) &middot; `[ ]` not started
- **Difficulty** rates implementing it *completely* (correct on real code + IDE-wired):
  - **Easy** -- single routine, pure text/AST, no data-flow, no type inference.
  - **Moderate** -- one file but needs def-use, a class-declaration edit, or light type work.
  - **Hard** -- cross-unit (needs the index + multi-file apply), real data-flow, or class surgery.
  - **Very Hard** -- class-hierarchy coordination, new-type synthesis, or deep semantic preservation.

## What makes a Delphi refactoring hard (the cost drivers)

1. **Cross-unit edits** -- must find every reference via the symbol index and edit many files (the `rename` machinery already does this; reuse it).
2. **Data-flow** -- needs the M2 CFG/def-use engine (general-CFG liveness is being built for Extract Method).
3. **Expression type inference** -- Delphi needs explicit types; the M1 resolver is symbol/hierarchy-level, expression-level typing is weak. *Escape hatch:* inline `var x := expr;` (Delphi 10.3+) lets the compiler infer the type, sidestepping most inference.
4. **Class-declaration surgery** -- inserting a member into the right `private`/`public` section, generating properties/getters, keeping the interface/implementation dual declaration in sync (rename already syncs headers).
5. **Class-hierarchy coordination** -- parents/children, visibility, `virtual`/`override`, abstracts -- the priciest.

---

## Shipped

| Refactoring | Status | Difficulty | Reuses / notes |
|---|---|---|---|
| Rename Symbol (cross-unit) | `[x]` v0.69 | Hard | Index callers + multi-file apply; conflict/reserved-word checks. The template for all cross-unit refactors. |
| Rename Local / Parameter | `[x]` v0.69 | Moderate | Pure-AST, routine-scoped; syncs matching forward/interface headers. |
| Find Unit (add to `uses`) | `[x]` v0.69 | Moderate | Index lookup + `uses`-clause edit. |
| Safe Delete | `[x]` v0.69 | Moderate | Refuses if the symbol has any caller (index). |
| Move `uses` interface&rarr;impl (`uses-fix`) | `[x]` | Moderate | Compiler-verified; also comments unreferenced units. A partial "Move". |
| (Generate doc-stub / test-stub) | `[x]` | Easy | Generation, not strictly a refactoring; listed for completeness. |

**Engine primitive:** `src/refactor/DRagLint.Refactor.TextEdit.pas` -- `TTextEdit` + `TTextEditApplier` (back-to-front multi-location apply, ANSI/CRLF-preserving, `.bak`, dry-run render). Every new refactoring builds on this.

---

## In progress -- current deployment

| Refactoring | Status | Difficulty | Notes |
|---|---|---|---|
| **Extract Method** | `[x]` v0.85 | **Hard** | v1 = single-file, value in-params + single `Result` output; REFUSES on 2+ outputs / conditional escape / escaping control flow / unknown types. CLI verb + IDE Ctrl+Alt+M, smoke-verified in the live IDE 2026-07-05. Built the reusable general-CFG liveness pass (`DRagLint.Analysis.Liveness.pas`). Spec: `docs/superpowers/specs/2026-07-03-extract-method-design.md`. |

---

## Local / single-routine (no index needed)

| Refactoring | Status | Difficulty | Reuses / notes |
|---|---|---|---|
| Introduce / Extract Variable | `[ ]` | Easy&ndash;Moderate | Select expression &rarr; `var v := expr;` (inline var dodges type inference) &rarr; replace occurrences. Easy with inline var; Moderate if an explicit type is required. |
| Inline Variable | `[ ]` | Moderate | Needs single-assignment + side-effect-free check (def-use) before substituting the initializer and deleting the decl. |
| Split Variable | `[ ]` | Moderate | We **detect** it (v0.83). Apply = rename the second live-range + declare a new local. Reuses local-rename + liveness. |
| Introduce / Declare Field | `[ ]` | Moderate | Like Introduce Variable but writes a class field (class-declaration edit). |
| Declare Variable | `[ ]` | Moderate | For an undeclared identifier; type inference is the cost (or use inline var). |
| Extract Resource String | `[ ]` | Moderate | Replace a string literal with a `resourcestring` + add its declaration. |
| Slide Statements (reorder) | `[ ]` | Moderate | Needs a dependency/def-use check to prove the move is safe. |

## Signature / call-site (reuses the index caller machinery)

| Refactoring | Status | Difficulty | Reuses / notes |
|---|---|---|---|
| **Change Signature** (add/remove/reorder params) | `[ ]` | Hard | Rewrites the decl + every call site; directly reuses rename's cross-unit caller edits. **Strong next pick after Extract Method.** New params get a default at call sites. |
| Parameterize Function / Remove Parameter | `[ ]` | Moderate&ndash;Hard | Change-Signature variants. |
| Remove Flag Argument | `[ ]` | Hard | Split a boolean-flagged call into two entry points; call sites branch on the flag &rarr; needs constant-arg analysis. |
| Introduce Parameter Object | `[ ]` | Very Hard | Synthesize a new record/class type + rewrite params + all call sites. |
| Preserve Whole Object / Replace Param with Query | `[ ]` | Hard | Data-flow at call sites. |

## Method-level

| Refactoring | Status | Difficulty | Reuses / notes |
|---|---|---|---|
| Inline Method / Function | `[ ]` | Hard | Substitute params + handle `Result` + collision-rename locals at every call site (cross-unit). Inverse of Extract Method. |
| Move Method (to another class) | `[ ]` | Hard | Rewrite `Self`/field access, visibility, and all call sites. |
| Replace Inline Code with Function Call | `[ ]` | Moderate | Find a block equal to an existing routine's body &rarr; replace with a call (clone detection already exists). |

## Encapsulation / field

| Refactoring | Status | Difficulty | Reuses / notes |
|---|---|---|---|
| Encapsulate Field (field &rarr; property) | `[ ]` | Hard | We **detect** `public-writable-field`. Apply = generate a property + getter/setter + rewrite direct external accesses (cross-unit). |
| Encapsulate Collection | `[ ]` | Very Hard | Wrap a collection field behind add/remove/read accessors. |

## Conditional / control-flow (mostly single-routine AST rewrites)

| Refactoring | Status | Difficulty | Reuses / notes |
|---|---|---|---|
| Decompose Conditional | `[ ]` | Moderate | Extract condition/branches into named helpers (leans on Extract Method). |
| Consolidate Conditional Expression | `[ ]` | Moderate | Merge sequential conditions with the same body. |
| Replace Nested Conditional with Guard Clauses | `[ ]` | Moderate&ndash;Hard | Control-flow rewrite (invert + early `Exit`). |
| Replace Control Flag with Break | `[ ]` | Moderate | We **detect** `loop-control-flag`. |
| Invert If / Split Loop / Consolidate Duplicate Fragments | `[ ]` | Moderate | Localized AST rewrites. |

## Class / hierarchy (the priciest tier)

| Refactoring | Status | Difficulty | Reuses / notes |
|---|---|---|---|
| Extract Interface | `[ ]` | Hard | Generate an interface from a class's public methods + add it to the class's declared interfaces. |
| Extract Superclass | `[ ]` | Very Hard | New base class + move members + reparent. |
| Pull Members Up / Push Members Down | `[ ]` | Hard | Hierarchy traversal + member move + visibility/override fixups. |
| Extract Class / Inline Class | `[ ]` | Very Hard | Split/merge responsibilities across types + rewrite all users. |
| Collapse Hierarchy | `[ ]` | Hard | Merge a parent/child pair. |
| Replace Conditional with Polymorphism | `[ ]` | Very Hard | We **detect** `repeated-type-switch`. Apply synthesizes a subclass hierarchy -- likely won't-do. |

## Deferred / low-value (unlikely to implement)

Replace Temp with Query, Replace Derived Variable with Query, Substitute Algorithm,
Replace Loop with Pipeline (no LINQ-equivalent in Object Pascal), Change Reference&harr;Value.
Weak payoff, high risk, or no clean static formulation.

---

## Recommended order (after Extract Method)

1. **Change Signature** -- highest value, reuses the proven cross-unit caller machinery.
2. **Introduce Variable** + **Inline Variable** -- cheap, high-frequency, build local-transform confidence.
3. **Split Variable (apply)** -- we already detect it; closes a detect&rarr;fix loop.
4. **Encapsulate Field** -- closes another detect&rarr;fix loop (`public-writable-field`).
5. **Extract Interface** -- first step into the hierarchy tier.

Everything above is invoked the same way: a CLI verb (`--dry-run`/`--apply`/`--json`/`--no-backup`) built on `TTextEditApplier`, wired into the IDE as a keyboard action that reads the editor selection, previews, applies, and reloads.
