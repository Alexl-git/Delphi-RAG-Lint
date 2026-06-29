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

### Phase 0 -- confirm the heritage AST (foundational, do FIRST)
Dump the parse tree of `type T = class(TBar, IBaz) end;` and `IFoo = interface(IBar) end;` with the
bundled `third_party/delphi-tree-sitter/ConsoleReadPasFile.dpr` (build via dcc). Record the exact node
type + field name for the ancestor list (likely `typeref` children of `declClass` before the first
`declSection`). **Everything else depends on this.** Capture findings in this doc.

### Phase 1 -- capture heritage
- ALTER `symbols ADD COLUMN heritage TEXT`; SCHEMA_VERSION 11; migration (`Schema.pas`, `SQLite.pas`).
- Parser: in `TryWalkClassOrRecord`/`TryWalkInterface`, read the Phase-0 node, store collapsed text.
- Plumb `heritage` through `TSymbol`, the insert/read SQL, `ReadSymbolFromQuery`.
- Test: index a fixture, assert `symbols.heritage` for a class with ancestors (a tiny `query --json`
  or a storage unit test under `tests/`).

### Phase 2 -- resolve ancestry + `IsDescendantOf`
- New `type_ancestors` table + DDL.
- `ResolveAncestry` pass (per design #4); call it after `ResolveUnitUseTargets` at the CLI index sites.
- `ISymbolStore.IsDescendantOf` + `Implements` (transitive walk over `type_ancestors`, library-DB
  by-name fallback, hop cap). Generalize `FormsMap.IsNavigableForm`'s logic; consider refactoring
  FormsMap to reuse it.
- Tests: a multi-unit project fixture (TChild in unit A `class(TBase)` in unit B) -> assert
  `IsDescendantOf('TChild','TBase')`; and an RTL case (`TStringList` descends `TPersistent`) via lib DB.

### Phase 3 -- type-category resolver
- `ResolveTypeCategory` (intrinsics + alias chase + symbol-kind) + `GetImplementedInterfaces`.
- Unit tests (a console test like `tests/projectchecks/`) over crafted type names + a fixture with
  `type TMyFloat = Double;` alias.

### Phase 4 -- upgrade the heuristic rules (the payoff)
Build `TTypeContext` from the store in the CLI lint-all/check-ast paths; thread into the checks with a
nil-safe fallback. Then:
- **float-equality**: operand category = tcFloat (resolved), drop the flat-map naming guess.
- **freeandnil-on-interface**: operand category = tcInterface (skInterface), drop the `I`-prefix.
- **win64-pointer-cast**: operand category = tcPointer, drop the `P`-prefix.
- **string-equality**: fire iff BOTH operands resolve to string categories (replace the `.scm` with a
  context-aware built-in, or keep `.scm` for the no-store path + a store-path built-in).
- **virtual-method-in-constructor**: extend the virtual-method set with inherited virtuals from
  ancestors via `GetVirtualMethodsIncludingAncestors` (cross-unit).
- Keep every existing fixture green; add negative+positive fixtures proving the exact behavior (e.g.
  `float-equality-string-fp` no longer needs the literal guard once types are real -- but keep it).

### Phase 5 -- library-DB ancestry + real-project validation
- Confirm ancestor resolution bridges into the library DB by name across the loaded DB set.
- Run `lint-all` on ORM3; confirm the upgraded rules' FP/precision improved (e.g. string-equality no
  longer fires on integer `=`; freeandnil-on-interface precision). Record before/after counts.

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
