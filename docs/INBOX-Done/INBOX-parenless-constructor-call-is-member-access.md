> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** REFUTED 2026-08-16: find-callers Create returns the parenless TOnlyOnce.Create as a CALL. (The unit-QUALIFIED receiver still does not resolve -- that is INBOX-qualified-type-receiver-does-not-resolve, still open.)

# INBOX: a paren-less `TFoo.Create;` is indexed as `member-access`, so it is invisible to every caller query

Found 2026-08-10 while building the schema-v20 receiver fixture.
Class: **unsupported construct** (the code is indexed; the construct is not
classified as a call).

## Reproducing

```pascal
unit repro;
interface
type
  TOnlyOnce = class
  public
    constructor Create;          // NO parameters
  end;
function MakeOne: TOnlyOnce;
implementation
function MakeOne: TOnlyOnce;
begin
  Result := TOnlyOnce.Create;    // NO parentheses -- idiomatic Delphi
end;
end.
```

```
drag-lint index <dir> --db r.sqlite
```

```sql
select kind, name_text from refs where name_text = 'Create';
-- member-access|Create        <-- NOT 'call'
select count(*) from call_edges;
-- 0
```

Expected: `MakeOne` is a caller of `TOnlyOnce.Create`.
Actual: no `call` ref, no `call_edges` row, and `query find-callers` reports
`0 caller(s)`.

Adding parentheses fixes it -- `TOnlyOnce.Create(1)` with a parameter, or
presumably `TOnlyOnce.Create()` -- so the discriminator is the ARGUMENT LIST, not
the callee.

## Why it matters beyond one ref kind

`ResolveCallTargets` streams only refs matching `CallSiteRefKindSql`, which is
`kind = 'call'` (`REF_KIND_CALL`, DRagLint.Core.Model). That same predicate
DEFINES the universe for the complement queries -- `FindUnresolvedNameCallers`
passes it as `ACallSitesOnly` -- so a `member-access` ref is excluded from BOTH
halves:

* it can never own a `call_edges` row, and
* it can never appear in the unresolved-name caller bucket either.

So a parameterless constructor call is not merely unresolved, it is absent. Every
consumer built on those two queries under-reports: `find-callers`, the
Auto-Document `Called from:` list, the call graph, call-path, and blast radius.

Parameterless constructors are extremely common in this codebase's style
(`TStringList.Create`, `TFDQuery.Create(nil)` is parenthesised but
`TObject.Create` is not), so the miss is not exotic.

## Suspected fix area

Wherever the parser classifies a dotted member reference: a member-access whose
resolved target is a ROUTINE kind should be emitted as `call` (or the call-site
universe should widen to include member-access refs whose target can be a call
target -- but note `CanBeCallTarget` is symbol-side and the ref is unresolved at
extraction time, so the parser-side fix looks more likely to be correct).

Do NOT widen `CallSiteRefKindSql` casually: its comment records that it is the
single definition of the call-site universe precisely so the resolved and
unresolved halves cannot disagree. Widening it changes both at once, which may be
right -- but it needs the argument written down, and the `member-access` refs that
are genuinely NOT calls (a field or property read, `Obj.FieldName`) must not
become fake call sites.

## Verification once fixed

`tests/callresolve/fixtures/receiver_bucket.pas` deliberately parenthesises every
call and says why in its header. A regression fixture for THIS defect should use
the paren-less form and assert a non-zero caller list.
