> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** RETIRED 2026-08-16 as STALE. out-param-not-set no longer appears in any YADF project (2 remain in DataCopy only), and object-leak is 1 shared-unit finding, not the spread recorded here. The surviving object-leak analysis lives in INBOX-object-leak-is-systematically-false.

# INBOX -- YADF triage 2026-08-12: two rules confirmed majority-false, one rule fixed

Companion to `INBOX-group-E-dataflow-rules-are-majority-false.md`, with the
specific source shapes that defeat each rule. Sampled against YADF at 156
findings (after `local-var-casing` went to 0).

## `local-var-casing` 79 -> 0 -- ALL of it fixed in YADF, none in the rule

**The rule was right and was left alone.** An earlier attempt here relaxed
`IsPascalCase` to tolerate a TRAILING underscore, on the reasoning that `Out_`
is the Delphi reserved-word escape and that renaming it to `Out` would not
compile. **The owner overruled that: PascalCase names do not contain
underscores, full stop, and the escape is to pick a real name.** The relaxation
was reverted (it never shipped -- no commit). Record the ruling, not the
attempt:

* `Out_`  -> `OutVal`   (18 occurrences)
* `My_Var_` -> `MyVar`  (the general form: drop the underscores, do not tolerate them)

So all 79 findings were REAL:
* 61 genuine camelCase locals (`iVal`, `origLine`, `semi`, `ty`, ...) -- renamed
  first-letter-uppercase. Those edits are case-only and byte-length preserving,
  verified case-insensitively identical to the originals, so they cannot affect
  compilation.
* 18 `Out_` -> `OutVal`. This one DOES change length, so it was verified with a
  real build: `msbuild /t:Build /p:Config=Debug /p:Platform=Win64 YADF.dproj`
  -> `BUILD_EXITCODE=0`, no errors.

`local-var-casing` is now 0 on YADF, and `IsPascalCase` still rejects every
underscore.

## FALSE ALARM 1 -- `out-param-not-set` vs the Try-pattern (7 of 7 on YADF)

```pascal
function TryParseExplicit(AVar: Integer; out ARec: TInlineRec): Boolean;
begin
  Result:= False;
  FirstName:= NextSig(AVar + 1);
  if (FirstName >= ATokens.Count) or (ATokens[FirstName].Kind <> ptIdentifier) then
    Exit;            // <-- ARec not assigned here
```

Literally true and contractually irrelevant. `TryXxx(...; out Y): Boolean` is a
universal idiom in which Y is defined ONLY when the function returns True, and
Delphi initialises `out` parameters on entry regardless. All 7 YADF findings are
this shape (`ARec`, across several `TryParse*` helpers).

**Suggested suppressor:** do not flag an `out` parameter when the routine is a
Boolean FUNCTION and every path that leaves it unassigned returns False. If the
dataflow for "returns False" is not available, the name-based form (Boolean
function whose name starts with `Try`) covers the idiom, since the Try prefix IS
the contract.

## FALSE ALARM 2 -- `object-leak` (3 of 3 on YADF)

Two distinct blind spots, both worth fixing separately.

**(a) Nested try/finally inside a try/except.** `YADF.Tokens.pas:266`:

```pascal
  Result:= TTokenList.Create;
  try
    Lex:= TmwPasLex.Create;
    try
      ...
    finally
      Lex.Free;          // <-- flagged anyway
    end;
  except
    Result.Free;
    raise;
  end;
```

Textbook-correct. The rule appears not to match the inner `finally` when it sits
inside an outer `try..except`.

**(b) Ownership transferred by the CONSTRUCTOR.** `YADF.Groups.pas:174`:

```pascal
  Cur:= TGroup.Create(gkUses, i, K, Cur);
...
constructor TGroup.Create(...; AParent: TGroup);
begin
  Children:= TObjectList<TGroup>.Create(True);   // owns its children
  if Assigned(AParent) then AParent.Children.Add(Self);   // <-- transfer
end;
```

Every node is owned by its parent's owning list, so freeing the root cascades.
The rule looks for a transfer at the CALL SITE and cannot see one performed as a
side effect of the constructor. Any tree/parent-linked type has this shape.

## Not false alarms, but worth a threshold conversation

`compiler-magic-comments` (16) does exactly what it says -- YADF really does
carry 16 TODO/FIXME comments. Working as designed; whether they are debt is the
author's call, not the linter's.

The complexity family (`deep-nesting` 16, `boolean-expression-complexity` 15,
`concat-in-loop` 15, `too-many-exit-points` 12, `cyclomatic-complexity` 9,
`cognitive-complexity` 7) and `duplicate-code` (29) measure what they claim. The
open question is threshold calibration for a tokeniser/layout engine, where long
`case` dispatch and repeated token-shape blocks are inherent. NOT yet sampled at
12 each -- next session's job.

## Cosmetic defect noticed while sampling

Dataflow findings lower-case the identifier in the message: `"arec"` for `ARec`,
`"out_"` for `Out_`, `"pendinglabel"` for `PendingLabel`. The text does not match
what the reader will find in the source, and it makes findings harder to grep.
