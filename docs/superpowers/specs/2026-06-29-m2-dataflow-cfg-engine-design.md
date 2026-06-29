# M2 -- Data-flow / CFG / def-use engine: design

> Status: approved 2026-06-29 (brainstorming). Successor milestone to **M1** (type/hierarchy resolver,
> complete -- see `docs/superpowers/plans/2026-06-29-m1-type-resolver-plan.md`). M2 is "the long pole":
> the per-routine control-flow + data-flow engine that unlocks the §3 (M2)-tagged checks in
> `docs/lint/MISSING-FEATURES.md` -- the real distance from ~60% toward PAL parity.
> Roadmap context: `docs/superpowers/specs/2026-06-28-lint-completeness-roadmap-design.md` (Wave/M sequence).
> This is a roadmap-level design; it decomposes into a `writing-plans` implementation plan, built in the
> staged order in section 10. Ship as its own version bump (after M1's v0.66/0.67).

---

## 1. Goal

Give drag-lint a **flow-sensitive analysis engine** -- a per-routine control-flow graph (CFG) plus a
generic monotone data-flow solver -- and deliver the high-value data-flow lint checks that are impossible
without it: definite-assignment (used-before-assignment, function-result-not-set, out-param-not-set),
liveness (dead stores, write-only locals), loop-variable-after-loop, and an interprocedural object-leak
check. The engine is a reusable substrate: future flow rules (Wave E cross-call ownership, thread-safety)
instantiate new lattices over the same CFG + solver rather than re-walking the AST.

## 2. Decisions (brainstorming 2026-06-29)

1. **Scope:** intraprocedural engine AND interprocedural object-leak in ONE milestone (user choice over a
   smaller first cut). Internally staged (section 10) with the CFG as the foundation.
2. **Reporting / FP stance:** **definite violations = `warning`, possible violations = `info`.** A
   "definite" violation holds on EVERY path to the use/exit; "possible" holds on SOME path (cf. the
   compiler's W1036 "may be undefined"). Any call passing `@var` / `var` / `out` ALWAYS counts as a
   possible assignment (suppresses the finding). Honors the roadmap FP policy ("when unsure, don't
   over-report; keep the rule").
3. **Rule set:** all four families -- definite-assignment, liveness/dead-stores, loop-var-after-loop,
   object-leak (interprocedural).
4. **Engine architecture:** a full **monotone dataflow framework** (lattice interface + worklist solver),
   each check expressed as an analysis instance -- the rigorous, extensible foundation (over the
   structured-AST-walk or single-check-PoC alternatives).

## 3. Architecture & units

Layered; each unit one purpose, narrow interface, consumed top-down. Mirrors the existing parse-cache /
`TAstChecker` conventions.

| Unit | Responsibility | Depends on |
|---|---|---|
| `DRagLint.Analysis.Cfg` | Per-routine **control-flow graph**: basic blocks + edges built from a `defProc` AST node. Pure data structure + builder; analysis-agnostic. | tree-sitter AST + parse cache |
| `DRagLint.Analysis.DataFlow` | Generic **monotone dataflow solver**: lattice interface (`Bottom`, `Join`, `Equals`, `Transfer`) + forward/backward worklist iterating a CFG to fixpoint. Analysis-agnostic. | `Cfg` |
| `DRagLint.Analysis.Flow.Lattices` | Concrete lattices + transfer functions: **definite-assignment** (forward must + may), **liveness** (backward may), **escape/ownership** (forward). | `DataFlow`, `Cfg` |
| `DRagLint.Diagnostics.FlowChecks` | The checks (`TFlowChecker`): run the right analysis per routine; map results to `TLintFinding` with definite=warning / possible=info. | `Flow.Lattices`, `Cfg` |

**Integration.** `TFlowChecker.Check(AFile [, AStore, AFileId])` mirrors the `TAstChecker.CheckXxx`
pattern: read the shared `TParsedFile` from the parse cache, return `TArray<TLintFinding>`. Wired into the
same three dispatch sites as the M1 rules: `DoLint` (bare `lint <file>`, store=nil), `DoLintAll`,
`DoCheckAst`. The intraprocedural checks need **no store** (per-file AST only) -> they run on the bare
`lint <file>` path and are testable by the standard `tests/lint/` fixture harness. Only the object-leak
check's interprocedural refinement takes an optional `ISymbolStore` (nil-safe, exactly like M1's
`CheckTypeAware`).

## 4. CFG model (`DRagLint.Analysis.Cfg`)

One CFG per routine body (`defProc`). A **basic block** is a maximal run of statements with one entry and
one exit. Two synthetic nodes: `Entry`, `Exit`. Construct mapping:

- `if` / `ifElse` -> block ends; edges to then-block and (else-block or join).
- `while` / `for` / `repeat` -> header + body + back-edge; the `for` header also **assigns** the loop var;
  loop exits to the follow block.
- `case` -> one edge per branch + else; join after.
- `Exit` / `Exit(v)` -> edge straight to `Exit` (and `Exit(v)` assigns `Result`).
- `Break` / `Continue` -> edge to the enclosing loop's exit / header.
- `try..finally` -> the finally block is on every path leaving the try (normal AND exceptional).
  `try..except` -> an edge from the **try region's entry** to the handler (conservative: anything assigned
  inside the `try` is NOT guaranteed in the `except` -- this keeps definite-assignment sound).
- `with`, inline `var x := ...`, nested routines (own CFG) -- see section 10.
- `asm` routine, or a routine containing `goto` -> **skip the whole routine** (conservative, like
  `CheckUnusedLocals`); `goto` would otherwise need unsound edges.

Exact tree-sitter node kinds (`while`/`for`/`repeat`/`case`/`try`/`kFinally`/`kExcept`/`Break`/`Continue`)
are **confirmed against real parses during implementation** (project standing rule: grep the actual
fixture, never trust assumed node names). The grammar discovery tool is
`C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse <file>`.

## 5. Dataflow framework (`DRagLint.Analysis.DataFlow`)

A generic monotone solver. An analysis supplies: a **lattice value** (a variable bitset; locals/params
indexed `0..N-1`), `Bottom`, `Join` (meet), `Transfer(block, inValue) -> outValue`, `Equals`, and a
`Direction` (forward/backward). The solver keeps `IN[b]` / `OUT[b]` per block and iterates a **worklist to
fixpoint**.

**Transfer functions** (per statement): `x := e` reads the vars in `e` then marks `x` assigned; a bare
read of `x` is a use-site; a call passing `@x` / `var x` / `out x` marks `x` assigned (FP-safe "might have
written it"); `Exit(v)` marks `Result` assigned; `raise` / `Exit` divert to the `Exit` node.

Two instances cover the assignment + liveness checks; escape is a third (section 7):

- **Definite-assignment** -- forward, must: `Join = intersection` (a var is definitely-assigned only if
  assigned on ALL incoming paths). A parallel **may**-assigned set uses `Join = union`. A read of `x`:
  `x` in neither must nor may -> definitely-uninitialized; in may-only -> possibly-uninitialized.
- **Liveness** -- backward, may: `Join = union`; powers dead-store + write-only detection.

## 6. The checks (`DRagLint.Diagnostics.FlowChecks`)

| Rule | Reads | Fires | Severity |
|---|---|---|---|
| `used-before-assignment` | definite-assign | read of an unmanaged local not in *must*-assigned set | neither must nor may -> **warning**; may-only -> **info** |
| `function-result-not-set` | definite-assign | `Result` not *must*-assigned at `Exit` | no path assigns -> **warning**; some-path -> **info** |
| `out-param-not-set` | definite-assign | `out` param not *must*-assigned at `Exit` (`var` params exempt) | **warning** |
| `overwrite-before-read` (dead store) | liveness | `x := ...` where `x` not live after, reassigned before any read | **info** |
| `write-only-local` | liveness | local assigned >=1x but never read anywhere | **info** |
| `loop-var-after-loop` | CFG + reaching | `for` control var read in a post-loop block, not reassigned | **warning** |
| `object-leak` | escape (section 7) | created object neither freed nor escaped on some path | **info** |

**Delphi semantics that keep this sound:**
- **Managed types are compiler-zero-initialized**, so `used-before-assignment` and
  `function-result-not-set` **skip** `string` / interfaces / `Variant` / dynamic arrays / managed records
  -- matching the compiler's W1036 (it warns only for unmanaged types). Detection: a **name heuristic** on
  the declared-type text when there is no store; **exact via M1 `ResolveTypeCategory`** when a store is
  present (nil-safe). Unmanaged (ordinal/float/pointer/enum/set/record-of-unmanaged/class-reference) is
  checkable.
- `Result` is modelled as an implicit local; `Exit(v)`, `Result := ...`, and the bare function-name
  assignment form all count as definitions.
- `var` params are treated as **assigned-on-entry** (may be in/out); only `out` params are required-to-set.
- `asm` routines and routines containing `goto` are skipped.

## 7. Interprocedural object-leak (escape analysis + call graph)

Track each local assigned from a constructor (`x := TFoo.Create(...)`). A forward **escape** lattice
records, per such var, whether on the current path it has been:
- **freed** -- `x.Free`, `FreeAndNil(x)`, `x.DisposeOf`; or
- **escaped** (ownership left the routine) -- `Result := x`, assignment to a field/property
  (`FX := x`, `obj.Y := x`), or **passed to any call** (`Bar(x)`, `List.Add(x)`, a ctor `Owner` arg);
  plus alias propagation (`y := x` carries x's state to y).

At `Exit`, a created var neither freed nor escaped on SOME path -> **leak (`info`)**. Because *any*
pass-to-call counts as escape, the store-free check fires only on clear cases (create, then fall out of
scope with no free and no escape).

**Interprocedural refinement (call graph / store).** The conservative "any call = escape" is sound but
misses leaks through *non-owning* callees. With an `ISymbolStore`, consult the call graph to recognize
callees that do NOT take ownership (so a genuine leak through them surfaces) and known owning sinks
(`OwnsObjects` list `Add`, `Owner`-param ctors, `.Free`). Store-free -> fully conservative; store-present
-> refined. Nil-safe optional-store pattern (as M1). This is the FP-riskiest check -> stays `info`-level.

## 8. Testing (TDD; harness stays green throughout)

- **Intraprocedural checks** -> standard `tests/lint/<id>.pas` + `.expected` fixtures (no store), each with
  positive AND negative cases (e.g. a var assigned on all branches = no fire; assigned on one branch then
  read = fire; assigned-on-all-but-one = info).
- **CFG + framework** -> a console unit test (`tests/flowengine/`, mirroring `tests/projectchecks/`)
  asserting block/edge structure + definite-assignment results, so the engine is verified independently of
  the checks.
- **object-leak interprocedural** -> a `tests/lint-project/`-style index+store fixture for the refined
  cases; conservative no-store cases via the normal harness.
- Every check: red -> green; DocInsight `///` on new public declarations; `.pas` strict 7-bit ASCII + CRLF.

## 9. Risks / Delphi gotchas

- **`with` statements** alias fields -> identifiers inside a `with` are treated as **opaque** (no
  used-before claim on them); a routine may be partly conservative rather than wrong.
- **Exceptions everywhere:** the try-region->handler edge is the soundness lever. Coarse = over-suppress
  (misses findings), which is acceptable per the FP policy (prefer misses to false positives).
- **`var` params** may legitimately be read before assignment (caller initialized) -> assigned-on-entry.
- **Nested routines** capturing outer locals -> an outer var captured by a nested routine is treated as
  possibly-assigned (conservative).
- **`Self.X` / field writes** are leak-escapes, not local definitions.
- **Performance:** per-routine CFG + fixpoint is cheap (routines are small); a whole-file / whole-project
  `lint-all` is many small CFGs -- acceptable. The parse-once cache is reused (no re-parse per check).
- **Grammar uncertainty:** node kinds for loops/case/try are confirmed empirically during implementation.

## 10. Internal phasing (one milestone, staged commits)

1. CFG builder + `tests/flowengine` unit tests.
2. Dataflow framework (lattice interface + worklist solver) + unit tests.
3. Definite-assignment lattice + the 3 checks (`used-before-assignment`, `function-result-not-set`,
   `out-param-not-set`) + fixtures.  <- first user-visible value.
4. Liveness lattice + `overwrite-before-read` + `write-only-local` + fixtures.
5. `loop-var-after-loop` + fixtures.
6. Escape lattice + `object-leak` (conservative, store-free) + fixtures.
7. Interprocedural ownership refinement (store-backed) + fixtures.
8. Managed-type precision via M1 `ResolveTypeCategory` on the store path.

Each stage: fixture -> green harness -> Win64 build -> commit. Wiring into the three CLI dispatch sites
lands with stage 3 (and is extended per stage).

## 11. Definition of done

`Cfg` + `DataFlow` + `Flow.Lattices` shipped with unit tests; the 7 checks live and wired into
`DoLint` / `DoLintAll` / `DoCheckAst` with definite=warning / possible=info; managed-type handling
heuristic (no store) + exact (store via M1); object-leak conservative store-free + refined store-present;
fixtures for every check; `tests/lint/run_lint_tests.ps1` green; a real-code sanity run recorded. Ship as
its own alpha version bump.
