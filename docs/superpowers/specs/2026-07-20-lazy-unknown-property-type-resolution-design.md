# Design: lazy unknown-property-type resolution (up-resolve, down-propagate, persist)

- Date: 2026-07-20
- Status: Approved (brainstorming complete; ready for implementation plan)
- Author: drag-lint session (resume LATEST-56 -> user follow-up)

## Motivation

`proptree` (the property tree used by the ConvRulesEditor, context bundles, and
hover) can only classify a property whose signature carries a concrete type. A
**bare redeclaration** (`property Align;` with no type) or a property inherited
across an **unresolved type-alias ancestor edge** (e.g.
`cxButtons.TcxBaseButton = Vcl.StdCtrls.TCustomButton`) surfaces as
`TypeName='unknown'` -- which then blocks conversion-rule casting (a mapping
`TAlign -> unknown` is rejected).

Prior work (commits `cddf48f` + `d6a1ab8`) made proptree walk **up** the class
tree to recover the type (`ResolveInheritedType`, then `ResolveViaBridgedAncestry`
bridging alias edges) and persist a bridged result with `MemoizePropertyType`
(`UPDATE symbols SET signature = ': <Type>' WHERE id = ...`,
`src/storage/DRagLint.Storage.SQLite.pas:2474`). But it is **incomplete**:

1. **No down-tree propagation.** Only the single queried property row is updated.
   The same unknown property on sibling/descendant classes stays unknown until
   each is separately queried.
2. **Only bridged resolutions persist.** A type recovered via the normal
   `ResolveInheritedType` path is recomputed every query, never written back.
3. **Lazy and partial** -- fires only for classes proptree happens to walk.

The user wants the resolution **completed** while keeping it **lazy** (no
proactive whole-index pass): *when a property query returns an unknown type, only
then* walk up the tree to recover the real type, walk **down** the tree persisting
that type onto every bare/unknown occurrence, and return the real type.

## Approach (user decision): lazy, query-triggered

Do NOT add a batch/index-time pass. Extend the existing query-time path in
proptree's `Walk` (`src/report/DRagLint.Convert.PropTree.pas:378-429`). The
trigger is unchanged: a property whose own signature is empty (the "unknown"
case). The additions are down-propagation and persisting all recovered types.

Trade-off accepted (user): query-time writes can contend with the shared ORM3
index while the IDE holds it open (SQLITE_BUSY). Mitigation stays best-effort
(see Persistence & contention).

## Algorithm

For each property leaf `P` on the queried class during `Walk`:

1. `OwnTok := ParseTypeToken(P.Signature)`. If non-empty, `P` already has a type
   -- nothing to do (no unknown, no write).
2. Else recover the type up-tree (existing order):
   a. `ResolveInheritedType(AClass, P.Name)` -- nearest resolved ancestor whose
      `P` carries a parseable signature.
   b. else `ResolveViaBridgedAncestry(AClass, P.Name)` -- climb, bridging
      unresolved (type-alias) ancestor names via
      `ResolveTypeNameToClass(name, AClass.FileId)`, returning the first KNOWN
      declared type. Never fabricates a type.
   Record `DeclClass` = the ancestor class on which the concrete type was found
   (the "declaring class"), and `T` = the recovered type token.
3. If `T = ''` -> stays `unknown`; **no** propagation, **no** write. (Nothing was
   recovered; the DB is left untouched.)
4. If `T <> ''`:
   a. **Persist on the queried row**: `MemoizePropertyType(P.Id, T)` -- for BOTH
      recovery paths (a) and (b), not just the bridge. (Idempotent: once written,
      step 1 short-circuits on the next query.)
   b. **Down-propagate**: enumerate descendant classes of `DeclClass`
      (`Store.FindDescendantNames(DeclClass.Name)`, backed by `type_ancestors`,
      the same engine as `query descendants --of`). For each descendant class `D`:
      find its child property named `P.Name`; if it exists AND its signature is
      **empty/bare** (an unknown redeclaration), `MemoizePropertyType(child.Id, T)`.
   c. Return `T` for the current node (existing behavior).

### The load-bearing safety rule

Down-propagation MUST update a descendant's property ONLY when that descendant's
own signature is empty/bare. A descendant that redeclares `P` with its **own
explicit type** (legal in Delphi, e.g. narrowing a property type) is NOT
overwritten -- doing so would corrupt a correct type. "Empty signature" is the
same bare-redeclaration test already used in step 1, so the guard is: parse the
descendant child's signature; skip if `ParseTypeToken <> ''`.

### Scope of "down the tree"

Propagate from **`DeclClass`** (the class that really declares the concrete type),
not merely from the queried class -- so all siblings that inherit the same bare
property are fixed in one shot, matching "traverse down the tree and update every
unknown." Descendants with a non-bare `P` are skipped per the safety rule.

## Components

1. **`Walk` extension** (`src/report/DRagLint.Convert.PropTree.pas`): thread the
   declaring class out of the up-tree resolvers so step 4b knows where to root the
   descendant walk; persist on both recovery paths; call the new propagation
   helper. Keep the existing cycle guard (`Visited`) and depth budget.
2. **`ResolveInheritedType` / `ResolveViaBridgedAncestry`**: return (or expose)
   the **declaring class** alongside the type token, so `Walk` can root the
   down-walk. Today they return only the token; add an out-param or a small record.
3. **Propagation helper** (private in PropTree, testable via a thin seam):
   `PropagateTypeToDescendants(DeclClass, PropName, T)` -- enumerate descendants,
   apply the safety rule, `MemoizePropertyType` each bare occurrence. Returns the
   count updated (for tests + telemetry).
4. **Store** already provides `FindDescendantNames`, `FindChildSymbolByName`,
   `ResolveClassByQName`/`FindSymbolByExactNameAnywhere`, and `MemoizePropertyType`
   -- no new storage surface expected. (If descendant enumeration needs class
   *symbols* rather than names, add a thin `FindDescendantClasses` that resolves
   the names it already returns.)

## Persistence & contention

- `MemoizePropertyType` is already **best-effort**: it no-ops on a read-only
  handle and swallows write errors (`src/storage/DRagLint.Storage.SQLite.pas:2478-2492`),
  so a query never fails on a write-lock. Down-propagation reuses it, so a busy DB
  simply skips the extra rows -- the queried row (step 4a) is attempted first and
  independently.
- **Idempotent**: a second query of any propagated property short-circuits at
  step 1 and performs no writes, so the subtree converges and steady-state has
  zero writes.
- **Open item carried from LATEST-54** (not resolved here): auto write-back opens
  the shared ORM3 index writable during LSP hover/context. Consider having the LSP
  pass `--no-write-back` on the shared index. This design does not change that
  posture; it only adds more (best-effort, idempotent) writes on first touch. If
  contention proves painful, the batch-index-pass alternative remains available.

## Testing (TDD)

Drive the propagation helper and the `Walk` integration with a fixture DB whose
class graph has: an ancestor `A` declaring `property Align: TAlign`; an
intermediate `B` that redeclares `Align` **bare** (empty signature) across an
unresolved alias edge; two leaf classes `C1`, `C2` descending from `B` that also
redeclare `Align` bare; and a `D` descending from `B` that redeclares
`property Align: TCustomAlign;` (explicit -- the safety case).

- Query `C1.Align` -> returns `TAlign`; assert the DB now has `TAlign` persisted on
  `B.Align`, `C1.Align`, AND `C2.Align` (down-propagation), and that `D.Align` is
  **untouched** (safety rule).
- Query a property that resolves via the normal (non-bridged) inherited path ->
  assert it is now persisted (gap #2 fixed).
- Query a property that genuinely dead-ends -> returns `unknown`, and assert **no**
  rows were written.
- Idempotency: re-run the first query -> assert zero additional writes
  (RowsAffected/updated-count = 0).
- Read-only store -> resolution still returns `TAlign`; assert no write attempted
  succeeds (no exception, best-effort).

## Out of scope / follow-ups

- A proactive batch/index-time pass over the whole index (explicitly rejected in
  favor of lazy; kept as a fallback option if contention becomes a problem).
- LSP `--no-write-back` on the shared index (separate, pre-existing follow-up).
- Multi-DB descendant propagation (propagate across sibling DBs) -- single store
  for now, matching how proptree already resolves.

## Open questions

None blocking. Contention posture is unchanged from today (best-effort writes);
the safety rule and propagation scope are settled above.
