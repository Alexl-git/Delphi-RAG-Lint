> # CLOSED 2026-08-16 (session 22) -- DOES NOT REPRODUCE. Both diagnoses were stale.
>
> Re-measured against current code. The defect is gone, and BOTH earlier
> statements about it were wrong:
>
> * The original note said `call_edges` held 1 row (only `MakeOne`). Measured
>   now: **2 edges**, and `find-callers --resolved` reports BOTH
>   `receiver_bucket.MakeOne` and `receiver_bucket.MakeQualified` as `[certain]`.
> * The session-21 banner said *"no `Create` ref exists in the index at all"* for
>   the qualified form. It does exist -- `find-callers` shows it at `:70:39`.
>   That banner sent readers to the ref EXTRACTOR, which was never the problem.
>
> `tests\callresolveun_receiver_bucket.ps1` already asserts *"both callers are
> RESOLVED (no uncertainty marker anywhere on the line)"* and passes, so this was
> fixed some time ago -- almost certainly by `TypeReceiver`'s Kind 7
> unit-qualified rung -- and the note was simply never closed.
>
> **One real coverage gap was found and filled.** `receiver_bucket.pas` qualifies
> with its OWN unit name, the easy case. Delphi FORCES qualification when two
> used units export the same type name, i.e. ACROSS units, and nothing pinned
> that. New `tests\callresolveun_receiver_qualified_cross_unit.ps1` +
> `fixtures\qual_decl.pas` / `qual_call.pas` cover it: cross-unit
> `qual_decl.TOnlyOnce.Create` resolves `[certain]`, with an unqualified call as
> the positive control and an unindexed dotted receiver as the negative control
> (so a resolver that matched every leaf name would fail).
>
> Original note follows, retained because its "suspected fix" describes what the
> shipped rung actually does.

> **RE-DIAGNOSED 2026-08-16 (session 21) -- the stated cause is already FIXED; the real one is upstream.**
>
> The note attributes this to receiver resolution. That half is done: `TCallResolver.TypeReceiver` has a **Kind 7** rung for exactly this shape (*"a UNIT-QUALIFIED TYPE receiver, 'Unit.TType.M'"*), taking the LAST segment as the type name, added in v20b.
>
> Measured on a one-file fixture holding both forms two lines apart:
> * `Result := TOnlyOnce.Create;` -> `find-callers Create` returns it (`:33:23`);
> * `Result := uParserGaps.TOnlyOnce.Create;` -> **no `Create` ref exists in the index at all**, and `query --text "TOnlyOnce.Create" --substring` finds nothing either.
>
> So `TypeReceiver` is never reached, because the REF IS NEVER EMITTED. The gap is in call-ref extraction for a multi-segment dotted callee, not in receiver typing. Anyone fixing this should start at the extractor, not at `CallResolver` -- the note as written sends them to code that already handles the case.
>
> Still OPEN, and still worth fixing: a unit-qualified constructor call is mandatory Delphi whenever two used units export the same type name.

# INBOX: a FULLY QUALIFIED type receiver (`Unit.TType.Create(...)`) never resolves

Found 2026-08-10 while building the schema-v20 receiver fixture.
Class: **unsupported construct** (indexed, but the resolver declines the shape).

## Reproducing

`tests/callresolve/fixtures/receiver_bucket.pas` has two real callers of
`TOnlyOnce.Create`:

```pascal
function MakeOne: TOnlyOnce;
begin
  Result := TOnlyOnce.Create(1);                    // resolves
end;

function MakeQualified: TOnlyOnce;
begin
  Result := receiver_bucket.TOnlyOnce.Create(2);    // does NOT resolve
end;
```

After `index`:

```sql
select name_text, receiver_text from refs where kind='call';
-- Create | TOnlyOnce
-- Create | receiver_bucket.TOnlyOnce     <-- receiver captured correctly
select count(*) from call_edges;
-- 1                                      <-- only MakeOne
```

So the RECEIVER TEXT is captured perfectly (v20's `refs.receiver_text` stores the
full dotted chain); it is the resolution step that gives up.

## Cause

`TCallResolver.TypeReceiver` rejects any dotted receiver outright:

```pascal
if not IsIdentStart(AReceiverExpr[1]) then Exit; // dotted / complex -> unhandled
for var i:= 1 to Length(AReceiverExpr) do
  if not IsIdentPart(AReceiverExpr[i]) then Exit; // e.g. 'A.B' chain -> unhandled
```

The second loop exits on the first `.`, so `receiver_bucket.TOnlyOnce` never
reaches the type-name rung (`ResolveTypeNameToSymbol`) that was added to fix the
107-caller bug.

## Impact

A unit-qualified constructor call is a real and idiomatic Delphi shape --
mandatory whenever two used units export the same type name, which is exactly
when a developer reaches for it. Such call sites form no `call_edges` row, so:

* `find-callers` under-reports them;
* the Auto-Document `Called from:` list reaches them only via the unresolved-name
  bucket, where they arrive marked ` ?` -- a REAL caller presented as uncertain.

The v20 receiver filter keeps them (it matches the LAST SEGMENT of the dotted
chain against the owner type, which is why `run_receiver_bucket.ps1` asserts
`MakeQualified` survives), so the fact is not lost -- it is merely downgraded.

## Suspected fix

In `TypeReceiver`, before giving up on a dotted receiver: split on '.', and if
every segment is an identifier, try `ResolveTypeNameToSymbol` on the LAST segment
(scoped to the ref's file, as the existing rung already is). Only bail when a
segment is non-identifier (a real expression such as `Arr[i].Foo` or a cast).

Keep the FP-conservative posture the rung already has -- resolve only when a
single certain candidate is found -- and note that the leading segments are a
UNIT qualifier, which could additionally be used to disambiguate two same-named
types rather than being discarded.

## Verification once fixed

`tests/callresolve/run_receiver_bucket.ps1` currently asserts `MakeQualified`
appears in the caller list. When this is fixed it should additionally lose its
trailing ` ?`, and `call_edges` for that fixture should be 2, not 1.
