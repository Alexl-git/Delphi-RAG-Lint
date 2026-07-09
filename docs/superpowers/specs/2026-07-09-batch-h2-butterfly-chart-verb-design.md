# Batch H2 -- `butterfly` chart verb (Track 5.3 slice) -- design

**Date:** 2026-07-09
**Status:** Approved (design); implement via TDD
**Context:** Deferred-backlog item after v1.0.0-alpha. Track 5.3 "architectural
charts" is large (butterfly + layering + module maps); this slice ships ONLY the
**butterfly chart** -- the static-export counterpart to the in-IDE butterfly
renderer already shipped in Batch F. Layering diagrams + module/architecture
overviews remain deferred as their own future items.

## Goal

A new CLI verb `drag-lint butterfly --qname X [--depth N] [--format dot|mermaid|text|json] [--output F] --db PATH [--db ...]`
that renders, in ONE output, the symbol X with its **callers (upward wing)** on
one side and its **callees (downward wing)** on the other -- the classic
"butterfly" call chart (compare SciTools Understand's butterfly view).

Read-only. Reuses the two shipped engines; **no new analysis engine**.

## Data

- Callers wing: `BuildReverseCallTree(store, rootId, depth)` (shipped).
- Callees wing: `BuildForwardCallTree(store, rootId, depth)` (shipped, Batch F).
- Both return the same `TRCallTree`/`TRCallNode`; the root qname is identical in
  both, so composing them shares the center node automatically.

## Composition (the key insight)

Charts dedupe nodes by id, and the existing `RenderNodeChart` keys nodes by
**qname**. So rendering both trees into one graph makes the root X appear once,
with the two wings attached:

- **Callers** render edges *into* the root: `caller -> callee` (i.e.
  `Kid.QName -> ANode.QName`) -- the existing reverse-tree emit direction.
- **Callees** render edges *out of* the root: `ANode.QName -> Kid.QName` -- the
  forward-tree emit direction (reverse of the caller edge orientation).
- `rankdir=LR` (dot) / `graph LR` (mermaid) already yields left-to-right wings:
  callers on the left flowing right into X, callees on the right flowing further
  right out of X.
- The **root node** is styled distinctly (e.g. dot `fillcolor="#ffd"`, bold) so
  the center of the butterfly is obvious. Caller nodes and callee nodes may get
  subtly different fill (optional; keep minimal).

Node-id collisions across wings: if a symbol is BOTH a caller and a callee of X
(a cycle through X), it appears once (same qname id) with edges on both sides --
correct and self-consistent. Cycle re-encounters within a wing keep the existing
`Cycle` marker + no-recurse policy.

## Verb behavior

- `--qname X` (required). Multi-db: first db that resolves X wins (mirror
  `DoReverseCallTree`'s `ResolveConsumerDbs` + first-non-empty-`ResolveEndpointIds`
  loop exactly).
- `--depth N` (default 3; `<0` clamped to 0) -- applied to BOTH wings.
- `--format dot|mermaid|text|json` (default `dot`, matching `graph`'s default;
  `reverse-calltree` defaults to text, but a *chart* verb defaulting to `dot` is
  more useful. Pick `dot` default; document it).
  - **text:** an indented two-section tree: `CALLERS (upward):` then
    `CALLEES (downward):`, each via the existing `RenderNodeText`.
  - **json:** `{ "schema": "butterfly/1", "qname": X, "callers": <reverse-tree
    root>, "callees": <forward-tree root>, "summary": {...both...} }` reusing
    `BuildTreeJson`/`BuildNodeJson` for each wing.
  - **dot/mermaid:** the composed butterfly graph above.
- `--output F` writes to a file (like `graph`/`deps-report`); else stdout.
- Exit 0 on success (even with zero callers and/or zero callees -- still a valid
  1-node chart); exit 1 if `--qname` resolves in no db; exit 2 on bad args / no
  readable db (mirror `DoReverseCallTree`'s exit codes).

## Engine helper

Add a small pure helper (near `RenderNodeChart` in CLI.pas, or reuse it): render
a forward tree's edges in the *out-of-root* orientation. The existing
`RenderNodeChart` emits `Kid -> ANode` (caller orientation); for the callees wing
we need `ANode -> Kid`. Either parameterize `RenderNodeChart` with an
`AReverseEdges: Boolean`, or add a sibling `RenderForwardChart`. Prefer the
parameter (one function, less duplication).

## Files

- `src/cli/DRagLint.CLI.pas` -- `DoButterfly` verb + dispatch line + usage line;
  the edge-orientation parameter on `RenderNodeChart` (or a sibling).
- `tests/autotest/run_butterfly.ps1` -- headless test.
- Docs: CHANGELOG, README (CLI list), AI-USAGE / AI-INDEX-FIRST (verb row).

## Testing (headless gate)

`run_butterfly.ps1` (build a fixture where X has >=1 caller AND >=1 callee, like
`run_forward_calltree.ps1`'s fixture but with a caller of the root too):
- `--format json`: schema `butterfly/1`, `qname==X`, `callers` root present with
  >=1 caller node, `callees` root present with >=1 callee node.
- `--format dot`: output contains `digraph`, contains the root qname, contains at
  least one `caller -> X` edge AND one `X -> callee` edge (assert both
  orientations present -- proves the two wings composed).
- `--format mermaid`: contains `graph LR` and both edge orientations.
- exit 0; a bogus `--qname` exits 1.

## Out of scope

Layering diagrams; module/architecture overviews (the rest of Track 5.3). No IDE
integration (the in-IDE butterfly tab already exists from Batch F; this is the
static-export sibling). No new engine.
