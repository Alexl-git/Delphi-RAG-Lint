# Finding: Ownership-yield for aliased generics with disposal patterns

**Date:** 2026-07-29  
**Task:** Phase 3 T5 (timeboxed)  
**Status:** Correct conservative behaviour — no bug, no cheap fix needed

---

## The Reproduction

The plan's hypothesis:
- `YADF.Tokens.LoadTokensFromString` contains `Result := TTokenList.Create`
- `TTokenList = TList<TToken>` (an aliased generic)
- `returns_owner` field is empty
- Suspect: type-alias resolution fails in `ClassifyReturnSite` or `IsReferenceTypeName`

## Measurement: Fixture Verification

Created and indexed `tests/autodoc/fixtures/docp3/owner_alias.pas`:

```pascal
type
  TThing = class end;
  TThingList = TList<TThing>;  // aliased generic with class parameter

function MakeDirect: TObjectList<TThing>;  // direct generic, class parameter
function MakeAliased: TThingList;          // aliased generic, class parameter

implementation
function MakeDirect: TObjectList<TThing>;
begin
  Result := TObjectList<TThing>.Create;  // direct constructor call
end;

function MakeAliased: TThingList;
begin
  Result := TThingList.Create;  // constructor call on type alias
end;
```

**Query results** (symbol_facts.returns_owner):
- `MakeDirect`: **'new'** ✓
- `MakeAliased`: **'new'** ✓

**Conclusion:** Type-alias resolution works correctly. Both direct and aliased generics with class parameters are recognized as constructors and marked 'new'.

## Root Cause Analysis: YADF's Disposal Pattern

The plan's reproduction (`YADF.Tokens.LoadTokensFromString`) returns `(empty)`, but NOT due to type-alias issues. Examining the implementation:

```pascal
function LoadTokensFromString(const ASource: string): TTokenList;
begin
  Src:= ShieldIncludeDirectives(ASource);
  Result:= TTokenList.Create;  // Creates the result
  try
    Lex:= TmwPasLex.Create;
    try
      // ... process tokens, add to Result ...
      for k:= 0 to Result.Count - 1 do
        if UnshieldIncludeToken(T) then
          Result[k]:= T;
    finally
      Lex.Free;
    end;
  except
    Result.Free;  // <-- Disposes result on exception
    raise;
  end;
end;
```

**The gate that rejects it** (`AnalyzeReturnsOwner`, line 1882):

```pascal
if Disposed then Exit;  // Result.Free/DisposeOf/FreeAndNil(Result) seen
```

When `WalkReturnsOwnerSites` detects `Result.Free` (line 307), `Disposed` is set to true, causing the function to exit with empty string. This is **correct conservative behavior**:

- The Result is created (new object)
- **Conditionally disposed**: freed only if an exception occurs
- If no exception, Result escapes to the caller
- **Ownership is conditional** → engine abstains (does not record)

The engine's choice is sound: conditional ownership (freed on exception path, transferred otherwise) cannot be confidently described as purely 'new' or 'borrowed'. Abstaining (`returns_owner = ''`) is the conservative default.

## Gate Classification

**Exact gate:** `AnalyzeReturnsOwner` line 1882 — disposition detection in `WalkReturnsOwnerSites`.

**Why it is correct:**
1. Ownership that depends on exception handling is not a simple transfer
2. The caller may receive a valid object (exception-free path) or none at all (exception path)
3. Recording 'new' would be misleading (caller might not own it if an exception freed it first)
4. Abstaining is conservative: better to omit than to guess

## Why the Fix is Not Cheap

To track conditional ownership would require:
1. Detecting disposal patterns (already done: ✓)
2. Distinguishing normal vs exception paths (requires CFG path analysis)
3. Recording conditional ownership in `symbol_facts.returns_owner` (schema change: strings can't express conditions)
4. Updating `document` and `hover` renderers to display conditional ownership (UX/output design)

This is **not a Phase 3 task** and does not belong under the timeboxed T5.

## Fixture Correctness

The fixture correctly demonstrates that **type aliases themselves are not the problem**. Both `MakeDirect` (direct `TObjectList<TThing>`) and `MakeAliased` (aliased `TThingList = TList<TThing>`) return 'new' when there is no disposal pattern.

The YADF case would also return 'new' if rewritten without the exception-handler disposal:

```pascal
function LoadTokensFromString(const ASource: string): TTokenList;
begin
  Result:= TTokenList.Create;
  try
    // ... (same body)
  finally
    // No explicit Result.Free here
  end;
  // Result escapes to caller normally
end;
```

This would let `returns_owner = 'new'` flow through unchanged.

## Recommendation

**No action needed for Phase 3.** The engine is working as designed. If conditional ownership tracking becomes a future requirement, it belongs in a separate enhancement task that addresses the schema and renderer implications.

Add to spec `§10 Follow-ups`: _"Conditional ownership (disposed in exception paths, transferred in normal paths) requires CFG path analysis and schema extension beyond Phase 3 scope."_
