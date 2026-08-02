# Design: Cross-DB Generic / Inherited Member Resolution (Hover item #2)

Date: 2026-07-24
Status: APPROVED (brainstorm 2026-07-24)
Topic: instance-member resolution on generic/alias types in `typeat` / hover

## Problem

Hovering an instance-member access whose member is **inherited** or lives on a
**generic base type** mis-resolves to an arbitrary same-named symbol.

Concrete case (YADF):

```pascal
ATokens: TTokenList;            // YADF.Tokens: TTokenList = TList<TToken>;
...
X := ATokens.Count;            // hover on `Count`
```

Today this shows the WRONG symbol `YadfMain.BatchFormat.Count` (an unrelated
local), and even in the best case "our info is much less" than the IDE, which
shows `property TList<YADF.Tokens.TToken>.Count: Int64`.

### Root cause

`TTypeAtResolver.Resolve` (`src/resolver/DRagLint.Resolver.TypeAt.pas:204-219`)
resolves the LHS type (`TTokenList`) then calls
`FindChildSymbolByName(LhsSym.Id, 'Count')`, which finds only **direct**
children. `Count` is not a direct child of the alias -- it is a property of the
generic base `System.Generics.Collections.TList<T>`. So the resolver falls into
the "owner type (member may be inherited)" branch and returns the alias type
itself. In the LSP, `HandleHover`'s guard `SameText(TAR.Resolved.Name, Ident)`
(`src/lsp/DRagLint.LSP.Server.pas:977`) then rejects that owner-type result and
falls back to `Symbols[0]` -- the arbitrary wrong local.

The resolver is also **single-store**, while the generic base `TList<T>` lives in
a DIFFERENT DB (`library-Win64`) than the project DB that holds the `TTokenList`
alias and the `ATokens` variable.

### Index facts (verified 2026-07-24)

- Alias `TTokenList`: `kind=type`, qname `YADF.Tokens.TTokenList`,
  `signature = "TList<TToken>"` (concrete generic argument in the signature).
- Generic base class: `name = "TList<T>"` (the `<T>` is part of the symbol name),
  qname `System.Generics.Collections.TList<T>`, in `library-Win64`.
- `Count`: `kind=property`, qname `System.Generics.Collections.TList<T>.Count`,
  `signature = "NativeInt"` (= Int64 on Win64), a DIRECT child of `TList<T>`.
- AMBIGUITY: a second `TList<T>` exists --
  `Spring.Collections.Lists.TList<T>`. Generic names are NOT uniform across the
  corpus (`TList<T>`, `TDictionary<TKey, TValue>`,
  `TObjectList<T: class, constructor>`), so matching must be by
  **base name + generic arity**, never string rewrite of `<TToken>` to `<T>`.

## Goals

- Hover / `typeat` on a generic-or-inherited instance member resolves to the
  REAL member symbol and renders its real signature (matches the IDE:
  `TList<T>.Count: NativeInt`).
- Never render a WRONG member. When resolution genuinely fails, degrade to the
  honest "owner type; member inherited" note -- not `Symbols[0]`.
- Battery-testable via the CLI (no live IDE required for regression coverage).

## Non-goals (deferred to the D5 resolved-reference milestone)

- Exact `uses`-clause-based disambiguation of ambiguous generic bases (this
  increment uses the RTL-preferred heuristic below).
- Resolved-reference scoping of the `.Count` CALLER filter (the "Used in" list
  for an instance-member access already correctly falls back to unfiltered
  project rows today; proper scoping needs D5).

## Architecture

### Multi-store `TTypeAtResolver`

Add an overload:

```pascal
class function Resolve(const AStores: TArray<ISymbolStore>;
  const AFile: string; ALine, ACol: Integer): TTypeAtResult;
```

- The PRIMARY store is the one that owns `AFile` (`FindFileIdByPath > 0`); if none
  owns it, `AStores[0]`. All resolution that is scoped to the hovered file
  (containing symbol, local-var inference, alias lookup) uses the primary store.
- The remaining stores are searched only for cross-DB TYPE / member resolution
  (the generic base and its members).
- The existing single-store `Resolve(AStore, ...)` becomes a thin wrapper:
  `Resolve([AStore], AFile, ALine, ACol)`. Every current caller is unchanged.

All new logic lives in the resolver -- the shared, testable primitive -- NOT in
`HandleHover`. HandleHover and `typeat` only differ in which store array they
pass.

### Member-resolution step (replaces the fallback at :204-219)

When `FindChildSymbolByName(LhsSym.Id, Token)` misses AND `LhsSym` is a
type-like symbol (`skClass, skRecord, skInterface, skTypeAlias`):

1. **Same-store ancestry.** Walk `PrimaryStore.GetTransitiveAncestors(LhsSym.Id)`;
   for each ancestor try `FindChildSymbolByName(anc.Id, Token)`. First hit wins.
   Fixes project-internal inheritance (`TFoo = class(TBar)` where both are in the
   same DB).

2. **Alias unwrap -> generic base (cross-store).** If `LhsSym` is an alias
   (`kind=type` with a non-empty signature naming another type):
   - Parse the underlying type from the signature: `BaseName` = identifier up to
     `<`; `Arity` = 1 + count of TOP-LEVEL commas inside the outermost `<...>`
     (nesting-aware, so `TDictionary<TKey, TList<T>>` = arity 2).
   - Search ALL stores for a `skClass` (or `skInterface`) symbol whose name is
     `BaseName` followed by `<` and whose own generic arity equals `Arity`.
     Candidate collection uses `FindSymbolByExactNameAnywhere` per store on the
     normalized formal name is NOT reliable (formal param spelling varies), so
     the match is: name starts with `BaseName + '<'` AND parsed arity matches.
   - On the chosen base, resolve `Token`: direct child via
     `FindChildSymbolByName`, else an ancestry walk IN THAT STORE
     (`GetTransitiveAncestors` on the base, e.g. `ToArray` on `TEnumerable<T>`).

3. **Return the real member.** `Result.Resolved` = the member symbol
   (`TList<T>.Count`), `HasResolved := True`, `OwnerTypeFallback := False`.
   Because `Resolved.Name = Token`, HandleHover's existing guard accepts it with
   NO guard change. The no-doc render path already prints qname + signature.

4. **Floor.** If steps 1-2 both fail, return the owner type (the LHS type) with
   the "member may be inherited" note AND set a NEW result flag
   `OwnerTypeFallback := True`. See the `TTypeAtResult` field + HandleHover change
   below -- this flag is what lets HandleHover render the honest owner-type note
   instead of silently falling back to the wrong `Symbols[0]`.

Multi-hop aliases (`A = B; B = C<T>`) are followed with a bounded loop + visited
set (cap depth, e.g. 8). A cycle or cap terminates to the floor.

### `TTypeAtResult` new field + HandleHover change

Add `OwnerTypeFallback: Boolean` to `TTypeAtResult`. It is `True` only in the
floor case (step 4): the resolver DID resolve the LHS type but could NOT find the
member on it or any ancestor/generic base.

HandleHover's post-resolve logic (`src/lsp/DRagLint.LSP.Server.pas:965-984`)
becomes:

- `HasResolved and SameText(Resolved.Name, Ident)` -> override `Sel` with the
  real member (existing full-success path; now also fires for generic/inherited
  members).
- `HasResolved and OwnerTypeFallback` -> render the honest owner-type note
  ("`<Type>.<Member>` -- inherited member; owner type `<QName>`") INSTEAD of
  `Symbols[0]`. This is the correctness floor: never a wrong member.
- otherwise -> today's behaviour.

Without this flag the floor cannot fire and the wrong `Symbols[0]` would still
show whenever step 2 fails -- so the flag is load-bearing, not cosmetic.

### Disambiguation policy (best-effort; exact = D5)

When step 2 finds MORE THAN ONE generic base matching (BaseName, Arity)
(e.g. Spring vs RTL `TList<T>`):

1. Prefer a `System.*` (RTL) qname over a third-party one; else
2. First match in store order.

Record the chosen owner and the fact that it was ambiguous in `Result.Note`.
Never fabricate: zero matches -> the floor. (Exact `uses`-closure disambiguation
is D5, per non-goals.)

## Data flow

```
hover ATokens.Count
  -> HandleHover passes FStores (all DBs incl. library) to Resolve
  -> primary store = YADF DB (owns YADF.Tokens.pas)
  -> LHS `ATokens` -> InferLocalVarType -> "TTokenList"
  -> LhsSym = YADF.Tokens.TTokenList (kind=type, sig "TList<TToken>")
  -> FindChildSymbolByName(alias, "Count") MISS
  -> step 1 ancestry (alias has no ancestors) MISS
  -> step 2: parse sig -> (TList, arity 1)
             search stores -> library-Win64 has System.Generics.Collections.TList<T>
             (+ Spring; disambiguate -> RTL preferred, note recorded)
             FindChildSymbolByName(TList<T>, "Count") -> property Count : NativeInt
  -> Resolved = System.Generics.Collections.TList<T>.Count
  -> HandleHover guard SameText("Count","Count") = True -> accept
  -> render: TList<T>.Count : NativeInt
```

CLI `typeat` gains multi-`--db` (resolve consumer DBs the way `DoHover` already
does) and passes the full store array to the new overload -- this is what makes
the cross-DB case battery-testable.

## Error handling

- File/line/col out of range, token empty, LHS unresolved: unchanged existing
  paths.
- Generic base not found in any store: floor (owner-type note).
- Ambiguous base: resolve best-effort + note; never fail hard.
- Member not found on the base or any of its ancestors: floor.
- Read-only stores: resolution is pure reads; no writes.

## Testing

Battery-first, TDD (RED before GREEN):

1. `tests/autotest/run_typeat_generic_member.ps1` (NEW):
   `typeat <YADF.Tokens.pas>:<Count-site line:col> --db <YADF> --db <library-Win64>`
   asserts resolved qname `System.Generics.Collections.TList<T>.Count` and
   signature `NativeInt`. RED asserts the current wrong/owner result first.
2. Same-store ancestry case: a project class inheriting a project class, member
   on the ancestor resolves (single DB).
3. Floor case: an unresolvable member returns the owner-type note, and the
   asserted qname is NOT some arbitrary unrelated symbol.
4. Regression: existing `run_hover_callsite.ps1` (6/6) + the autodoc/hover
   battery stay green (single-store wrapper unchanged).
5. Live-IDE manual verify LAST: hover `ATokens.Count` in YADF -> real signature.

## Files touched

- `src/resolver/DRagLint.Resolver.TypeAt.pas` -- multi-store overload + steps 1-2
  + generic-arity parser + disambiguation.
- `src/cli/DRagLint.CLI.pas` -- `DoTypeAt` resolves consumer DBs + passes the
  store array; single `--db` still works.
- `src/lsp/DRagLint.LSP.Server.pas` -- the two `TTypeAtResolver.Resolve(...)`
  calls in `HandleHover` pass `FStores` instead of a single store; the
  post-resolve logic honors the new `OwnerTypeFallback` flag (render honest
  owner-type note, never `Symbols[0]`).
- `tests/autotest/run_typeat_generic_member.ps1` -- NEW.

## Rebuild / deploy

CLI exe via `build/build_draglint_win64.bat`; plugin BPL via
`build_plugin_win32.bat` -- both PowerShell `Start-Process -Wait`, require
`0 Error(s)`. **IDE MUST BE CLOSED** to deploy (LSP `drag-lint.exe` + `bds.exe`
lock the exe/BPL). Since resolution moves into the shared resolver, the CLI exe
change is what the LSP spawns; the BPL only needs a rebuild if item #1/#3 (the
other two hover-polish items) touch the plugin -- which they do.

## Constraints reminder

`.pas` strict 7-bit ASCII, CRLF, no BOM. DocInsight on new public decls
(the `Resolve` overload). Block `{ }` comments must not contain `{`, `}`, or
`...` (comments do not nest -- a repeated trap); use `//` for anything naming
JSON shapes or generic braces.
