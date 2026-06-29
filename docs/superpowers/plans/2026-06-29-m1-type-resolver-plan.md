# M1 -- Type & Hierarchy Resolver: design + phased implementation plan

> **Status:** executable plan for the next milestone (chosen by the user 2026-06-29 over the
> naming wave / project-membership / rule-UI alternatives). Big, multi-session. Baseline:
> origin/main @ d845976 (v0.65.1 shipped; harness 80/80). Implement phase-by-phase, each phase
> green on `tests/lint/run_lint_tests.ps1` + new unit/project fixtures before the next.

## Goal
Give drag-lint **scope-resolved declared types** and a **cross-unit class/interface hierarchy**,
so the rules that are heuristic today become exact, and the type-dependent rule family becomes
possible. Concretely, upgrade five shipped heuristics and unblock the cast family.

## Why (what's wrong today) -- verified substrate
- `symbols` (SCHEMA_VERSION=10, `src/storage/DRagLint.Storage.Schema.pas:20-27`) stores
  id/file_id/parent_id/kind/name/qualified_name/signature/modifiers/section/lines. **No ancestor
  column; no var/param declared-type; `modifiers` = visibility only.** Field/property/const type
  text is squeezed into `signature`.
- The parser `TryWalkClassOrRecord` (`src/parser/DRagLint.Parser.Delphi13.pas:386`) reads class
  name + members but **never the `(TBar, IBaz)` heritage list**.
- `refs.kind='type_use'` records typeref sites but unresolved (`name_text` only).
- `unit_uses.target_file_id` (resolved by `ResolveUnitUseTargets`, `SQLite.pas:2336`) **is the
  cross-unit scope graph** M1 builds on.
- The heuristic rules: `float-equality-comparison` + `freeandnil-on-interface` + `win64-pointer-cast`
  share `CheckTypeAware`'s **flat, scope-free `TypeMap`** (`AstChecks.pas:1357-1576`, naming-convention
  `IsInterfaceType`/`IsPointerType`); `string-equality-comparison` is a `.scm` regex; 
  `virtual-method-in-constructor` is **same-file/same-class only** (`AstChecks.pas:3531`).
- **Prior art to generalize:** `DRagLint.FormsMap.pas` (`ReadAncestor:80`, `IsNavigableForm:113`)
  already walks the cross-unit ancestor chain by name (text-parsed, per-query, VCL-base terminators,
  16-hop cap). M1 = the indexed, AST-captured, persisted version of that.
- Library DBs `library-Win64/Win32.sqlite` hold RTL/VCL ancestry; cross-DB ids are DB-local, so
  resolve ancestors **by name across the loaded DB set** (the `IsNavigableForm` pattern).
- Roadmap already scopes this: `docs/lint/BACKLOG.md:78-93`.

---

## Design decisions (autonomous; review before implementing)

### Storage
1. **`symbols.heritage TEXT`** (ALTER, bump SCHEMA_VERSION -> 11; idempotent ALTER per
   `SQLite.pas:319-425`). Raw heritage text the parser captures, e.g. `TBar, IBaz`. NULL for
   non-class/interface or no ancestors.
2. **New table `type_ancestors`**: `(symbol_id INTEGER, ordinal INTEGER, ancestor_name TEXT,
   ancestor_kind TEXT /* 'class'|'interface'|'?' */, ancestor_symbol_id INTEGER NULL,
   ancestor_file_id INTEGER NULL)`, indexed on `symbol_id` and `ancestor_name`. Populated by the
   resolve pass; `ancestor_symbol_id` NULL = unresolved (external/RTL/by-name only).
   Direct edges only (not transitive); transitive walk done at query time (cheap, cached).

### Resolution (post-index whole-DB passes, parallel to `ResolveUnitUseTargets`)
3. **Capture pass (parser):** confirm + read the heritage AST node, store `heritage` text on the
   class/interface symbol.
4. **`ResolveAncestry` (new `ISymbolStore` method, beside `ResolveUnitUseTargets`,
   `Core.Interfaces.pas:94`):** for each class/interface with `heritage`, split names, and for each
   resolve to a defining symbol using the file's in-scope `unit_uses.target_file_id` candidate set
   (fallback: `FindSymbolsByExactName` + prefer in-scope file; then library DB by name). Write
   `type_ancestors` edges. Terminate/标记 unresolved like `IsNavigableForm` (VCL bases, 16-hop cap).
5. **Type-category resolver `ResolveTypeCategory(typeName, fileId): TTypeCategory`**
   (`tcFloat|tcString|tcOrdinal|tcBoolean|tcInterface|tcClass|tcPointer|tcEnum|tcUnknown`): intrinsics
   by name first (Double/Single/Extended/Real->float; string/AnsiString/UnicodeString/WideString->
   string; Integer/Cardinal/Int64/...->ordinal; Boolean->boolean; Pointer/P*->pointer); then resolve
   a `type X = Y` alias via the index (chase to a fixpoint, cap depth); then class/interface by the
   resolved symbol's `kind`.

### Rule API + how rules consume it
6. **`TTypeContext`** -- a per-file bundle the CLI builds from the store after indexing (name->category
   map for the file's decls + `IsDescendantOf`/`Implements` closures over `type_ancestors` + library
   DB). Passed (optionally) into `CheckTypeAware` / `CheckVirtualInConstructor`. **When nil (the bare
   `lint <file>` path with no store), fall back to today's heuristics** so single-file lint still works;
   the store-bearing paths (`lint-all`, `check-ast`, MCP `Check(AStore,AFile)`) get exact resolution.
   New store methods: `IsDescendantOf(klass, ancestor, fileId)`, `Implements(klass, intf, fileId)`,
   `ResolveTypeCategory(...)`, `GetVirtualMethodsIncludingAncestors(klass, fileId)`.

### Incremental
7. Resolve passes are whole-DB (like `ResolveUnitUseTargets`) -- run after the symbol/refs/uses passes
   from the same CLI sites (`CLI.pas:1034,1522,1569`). Whole-DB resolve first (simple/correct);
   changed-file+dependents scoping is a later optimization.

---

## Phases (each: TDD fixture -> implement -> harness green -> Win64 build -> reindex -> commit)

### Phase 0 -- confirm the heritage AST (foundational, do FIRST) -- DONE 2026-06-29
Dumped via `C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse <fixture>` (no dcc build needed; the
bundled exe parses .pas directly). **CONFIRMED findings:**
- Ancestor list = named **`parent:` fields**, one per ancestor, each node kind **`typeref`**, sitting as
  **direct named children** of the `declClass` (class/record) / `declIntf` (interface) node. Multiple
  ancestors -> multiple `parent:` typeref children, in source order. They are the ONLY bare `typeref`
  direct children (members live inside `declSection`/`declField`/...), so the capture can just collect
  direct named children of kind `typeref`.
- Class node = `declClass`, wrapped in a `(type ...)` node under the declType's `type:` field (parser
  already finds it via `FindNamedChildOfType(TypeWrapNode,'declClass')`, `Delphi13.pas:401`).
- Interface node = `declIntf`, sits **directly** under the declType `type:` field (no `(type)` wrapper)
  (`Delphi13.pas:433-435`).
- Ancestor name shapes inside a `typeref`:
  - plain: `typeref > identifier` (e.g. `TBar`, `IBaz`).
  - qualified: `typeref > typerefDot` with nested `lhs/operator(kDot)/rhs` -> dotted tail = innermost
    `rhs` identifier (e.g. `System.Classes.TComponent` -> `TComponent`).
  - generic: `typeref > typerefTpl` with `entity:` identifier = base name (strip `<...>`), e.g.
    `TList<TFoo>` -> `TList`.
- Capture plan: store collapsed raw heritage text (e.g. `TBar, IBaz`) on the symbol via `NodeText` of
  each `typeref` joined by `, `; the resolve pass (P2) does name normalization (strip `<...>`, dotted tail).

### Phase 1 -- capture heritage -- DONE 2026-06-29
- ALTER `symbols ADD COLUMN heritage TEXT`; SCHEMA_VERSION 10->11; migration (`Schema.pas` CREATE +
  `SQLite.pas` Migrate ALTER, before PrepareStatements so the INSERT's `:her` col exists).
- Parser: new `HeritageTextOf` collects the bare `typeref` named children of `declClass`/`declIntf`,
  whitespace-collapses each, joins with `, `; wired into `TryWalkClassOrRecord` (passes `ClassNode`) and
  `TryWalkInterface` (passes `TypeNode`/declIntf) via a new optional `AHeritage` param on `Emit`.
- Plumbed `heritage` through `TSymbol.Heritage`, the INSERT SQL + `UpsertSymbol` (`her` param, NULL when
  empty), `ReadSymbolFromQuery` (FindField-guarded for pre-v11 DBs), and `query --json` (omitted when empty).
- Test: `tests/heritage/` (fixture + `run_heritage_test.ps1`): index -> `query --name <T> --json` ->
  assert heritage. Covers class+iface (`TBar, IBaz`), iface-parent (`IBar`), no-ancestor (empty/NULL),
  and verbatim qualified (`System.Classes.TComponent`) + generic (`TBar, IList<IBaz>`) capture. 5/5 green;
  full lint harness 80/80; baseline RED confirmed first (TFoo/IFoo had no heritage field).

### Phase 2 -- resolve ancestry + `IsDescendantOf` -- DONE 2026-06-29
- `type_ancestors(symbol_id, ordinal, ancestor_name, ancestor_kind, ancestor_symbol_id, ancestor_file_id)`
  + 2 indexes, created in `Migrate` via TryExec (avoids renumbering the SCHEMA_DDL FTS5 split index;
  plain DDL that must always exist). `ON DELETE CASCADE` on symbol_id.
- `ResolveAncestry` (SQLite.pas): whole-DB pass mirroring `ResolveUnitUseTargets`. Builds an in-memory
  name->candidates map (class/interface symbols) + per-file in-scope set (from `unit_uses.target_file_id`),
  splits each heritage (top-level-comma aware, generics safe), normalizes each token (`NormalizeAncestorName`:
  strip `<...>`, dotted tail), resolves to a defining symbol (exactly-one-in-scope, else single-global; else
  unresolved kind '?' per FP policy), and rebuilds `type_ancestors`. Wired after all 3 `ResolveUnitUseTargets`
  CLI sites. Heritage is read from the index now -- no per-query `.pas` text-scan (unlike FormsMap.ReadAncestor).
- `ISymbolStore`: `GetTransitiveAncestors` (BFS, cycle-safe, hop-capped, resolved edges expanded /
  unresolved name-only leaves), `IsDescendantOf`, `ImplementsInterface` (thin wrappers via private
  `ResolveTypeSymbolId`, prefer in-file definition). `Implements` renamed to `ImplementsInterface` (avoid
  the `implements` directive). Library-DB by-name fallback deferred to Phase 5.
- New CLI surface `query ancestors --name <T> [--of <A>] [--json]` (transitive closure; `--of` = is-descendant
  + implements). Test: `tests/heritage/ancestry/` (unita uses unitb) + `run_ancestry_test.ps1`: cross-unit
  transitive class chain (TChild->TBase->TGrand), cross-unit iface parent (IChild->IBase), implemented-iface
  edge, resolved-kind check, is-descendant/implements via `--of`. 9/9 green; lint harness 80/80; v10->v11
  migration verified on an existing DB (no crash, table+column added).

### Phase 3 -- type-category resolver -- DONE 2026-06-29
- `TTypeCategory` enum (tcUnknown/Float/String/Char/Ordinal/Boolean/Interface/Class/Record/Pointer/Enum)
  + `ToText` in Core.Model.
- `ISymbolStore.ResolveTypeCategory(typeName, fileId)`: intrinsics by name first (IntrinsicCategory:
  float/string/char/boolean/ordinal sets + Pointer + `P[A-Z]` heuristic), then a declared
  class/interface/enum/record symbol's kind, chasing `type X = Y` aliases to a fixpoint (depth cap 8,
  prefer in-file definition). 
- Parser: new `TryWalkAlias` emits **skTypeAlias** for simple type-reference aliases (`type X = SomeType;`,
  direct `typeref` target only -- sets/subranges/proc-types/classes/etc. skipped), storing the target in
  `Signature` so the resolver can chase it. Wired into the declType dispatch after TryWalkEnum.
- CLI `query typecat --name <T> [--json]`. Test `tests/heritage/typecat.pas` + `run_typecat_test.ps1`:
  intrinsics (Double/Single/string/Integer/Boolean/Char/Pointer/PChar), declared class/interface/enum,
  alias->intrinsic + alias->alias->intrinsic chase, unknown. 14/14 green; lint harness 80/80; heritage +
  ancestry regressions green (skTypeAlias emission did not regress them).
- (Deferred: `GetImplementedInterfaces` not needed -- `ImplementsInterface` (P2) covers the rule need.)

### Phase 4 -- upgrade the heuristic rules (the payoff) -- CORE DONE 2026-06-29 (3 of 5)
Threaded an optional `(AStore, AFileId)` into `CheckTypeAware` (no separate TTypeContext type -- direct
params, YAGNI). Decision policy: **store category authoritative when known (<> tcUnknown), name heuristic
fallback otherwise** -- this both catches non-conventional types AND suppresses the heuristic's FPs, while
the nil path (bare `lint <file>`) is byte-for-byte unchanged so the 80-fixture harness is untouched.
- **float-equality** DONE: operand category = tcFloat (resolved, incl. alias chase); heuristic fallback.
- **freeandnil-on-interface** DONE: tcInterface authoritative (catches non-`I` interfaces; suppresses the
  `I`-prefixed-CLASS false positive); `I`-prefix fallback when unresolved.
- **win64-pointer-cast** DONE: tcPointer resolved; `P`-prefix fallback.
- Wired store into `lint-all` (5252) + `check-ast` (DoCheckAst) call sites; `lint <file>` (4392) stays nil.
- Test: `tests/heritage/typeaware/tc_store.pas` via `check-ast --db --format json` (3 divergence cases),
  3/3 green; harness 80/80. Committed b4aafb5.
- **DEFERRED (2 of 5), documented blockers:**
  - **virtual-method-in-constructor cross-unit** -- BLOCKED: method virtual/dynamic/override-ness is NOT
    indexed (`symbols.modifiers` = visibility only). Needs a capture mini-phase (emit method directives,
    like heritage was) before `GetVirtualMethodsIncludingAncestors` can read ancestor virtuals from the
    index. The rule stays same-file/same-class (today's behavior) until then.
  - **string-equality** -- DEFERRED: the `.scm` rule (info-severity) already runs on every path incl.
    lint-all; a store-path built-in firing on `both operands resolve to tcString` would DUPLICATE it unless
    the `.scm` is suppressed on the store path. Needs a coexistence design (built-in + per-path `.scm`
    disable, or a resolver post-filter on the `.scm` finding). Low stakes (info). 

### Phase 4b (follow-up) -- finish the last 2 rules
- Capture method modifiers (virtual/dynamic/override/abstract/reintroduce) in the parser -> symbols (new
  column or extend modifiers); `ISymbolStore.GetVirtualMethodsIncludingAncestors(klass, fileId)`; thread
  store into `CheckVirtualInConstructor`; cross-unit fixture (ctor calls an ancestor-declared virtual).
- string-equality store path per the coexistence design above.

### Phase 5 -- library-DB ancestry + real-project validation -- PARTIAL 2026-06-29
- **Real-code validation DONE:** indexed `src/` and confirmed on real types -- `TDelphi13Parser` ->
  ancestors `IParser` (resolved=true, cross-unit) + `TInterfacedObject` (resolved=false, kind '?', since
  it lives in the RTL/library DB not in `src/`); `--of IParser` -> is_descendant+implements both true;
  enums -> tcEnum. Proves cross-unit ancestry + category resolution work on real code, and shows exactly
  where the cross-DB bridge is needed (the unresolved RTL bases).
- **DEFERRED -- cross-DB library bridge:** `ResolveAncestry`/`GetTransitiveAncestors`/`ResolveTypeCategory`
  currently resolve within ONE store/connection (the project DB). RTL/VCL bases (TComponent, TForm,
  TInterfacedObject, TPersistent) live in `library-Win64/Win32.sqlite`, so they resolve by NAME only
  (unresolved edge, kind '?') -- the transitive walk can't step INTO them. To bridge: make the resolve pass
  / walk consult the loaded library DB by name (the `IsNavigableForm` cross-DB-by-name pattern). Until then,
  IsDescendantOf still matches a direct RTL base by name, but not its grand-ancestors; ResolveTypeCategory
  falls back to the heuristic for RTL types (acceptable).
- **DEFERRED -- ORM3 before/after counts:** run `lint-all` on ORM3 (with Platform+Project DBs) and record
  FP/precision deltas for the 3 upgraded rules once the cross-DB bridge lands (otherwise RTL operands
  resolve tcUnknown and fall back to heuristic, so the delta would understate the gain).

---

## Risks / notes
- **Heritage node name is unverified** -- Phase 0 gates everything. If the grammar exposes ancestors
  differently than expected, adjust capture.
- **Generics/qualified ancestors** (`class(System.Classes.TComponent)`, `TList<T>`) -- normalize names
  (strip `<...>`, take the dotted tail) consistent with `NormUnit`/`unit_name_norm`.
- **Shadowing / same-name classes across units** -- resolve in-scope first (uses-graph), then by name;
  record ambiguity as unresolved rather than guessing (FP policy: when unsure, don't claim).
- **Performance** -- whole-DB resolve on ORM3 (~1.5M symbols) must stay sub-minute; batch UPDATEs like
  `ResolveUnitUseTargets`, single pass, prepared statements.
- **Don't break `lint <file>`** -- the no-store path keeps the heuristic fallback.

## Definition of done
SCHEMA 11 with `heritage` + `type_ancestors`; `ResolveAncestry` + `IsDescendantOf`/`Implements`/
`ResolveTypeCategory` on the store; the five rules upgraded to exact on store-bearing paths with
fixtures; harness green; ORM3 before/after recorded. Ship as **v0.67.0-alpha**.

## STATUS 2026-06-29 (autonomous run) -- M1 CORE COMPLETE, release-ready, NOT yet cut
Commits on `main` (all green, harness 80/80 throughout): 9ffc642 (P1 heritage, SCHEMA 11),
ed65c22 (P2 type_ancestors + ResolveAncestry + IsDescendantOf/Implements + `query ancestors`),
63e8104 (P3 ResolveTypeCategory + skTypeAlias capture + `query typecat`),
b4aafb5 (P4 core: float-equality / freeandnil-on-interface / win64-pointer-cast store-aware).
New tests: tests/heritage/{run_heritage,run_ancestry,run_typecat,run_typeaware}_test.ps1 (31 assertions).
**DELIVERED:** the resolver infrastructure (capture -> resolve -> category) + 3 of 5 rule upgrades +
real-code validation. **REMAINING for full DoD:** P4b (virtual-in-ctor cross-unit -- needs method
virtual-ness indexed; string-equality store path -- coexistence design), P5 cross-DB library bridge +
ORM3 before/after. **Release:** not cut (VERSION still 0.65.1) -- user wants M1+M2 bundled; bump to
v0.66/v0.67 when cutting. The 4 phase-test runners are NOT yet wired into a single suite runner.
