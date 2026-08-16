> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21). FIXED.** `LhsBaseIdent` peels a dotted lhs to its LEFTMOST identifier, so `Result.FActive := True` credited the write to `Result` and `Self.FField := x` to `Self` -- neither a field, so no write was recorded. Both receivers are now credited to the member. All 3 live findings on our own source (`Project.OwnRoots.pas` FDeclared/FError/FActive) cleared, and a genuinely never-written field still fires. Guarded by `tests\autotest\run_referenced_never_set_receivers.ps1` (4/4). **Deliberately limited to `result`/`self`** -- crediting the member of any dotted lhs would mis-attribute `SomeOther.FField := x` and suppress real findings. **Known remaining gap:** the pass is CLASS-SCOPED, so `Result.F := x` in a STANDALONE function is still unseen; the real-world shape is a class function of the type, which is covered.

# referenced-never-set false-positives on record-factory `Result.FField := ...`

**Class:** unsupported construct (parser/rule-extractor gap, not a stale index).
**Found:** 2026-08-11, during code review of Task 4
(`docs/lint/... 2026-08-11-project-drag-lint-home-and-lint-ownership`,
`DRagLint.Project.OwnRoots.pas`).

## Reproducing command

```
src\cli\Win64\Debug\drag-lint.exe lint src\project\DRagLint.Project.OwnRoots.pas --rule referenced-never-set
```

## Actual output (captured, unedited)

```
src/project/DRagLint.Project.OwnRoots.pas:36:5  [warning] referenced-never-set: Field "FDeclared" is read but never written -- it always holds its zero value
src/project/DRagLint.Project.OwnRoots.pas:37:5  [warning] referenced-never-set: Field "FError" is read but never written -- it always holds its zero value
src/project/DRagLint.Project.OwnRoots.pas:38:5  [warning] referenced-never-set: Field "FActive" is read but never written -- it always holds its zero value
3 finding(s)
```

## Source snippet that triggers it

`src\project\DRagLint.Project.OwnRoots.pas` -- a value-type "record factory":

```pascal
  TOwnRoots = record
  strict private
    FRoots   : TArray<string>;
    FAnchor  : string        ;
    FDeclared: Boolean       ;
    FError   : string        ;
    FActive  : Boolean       ;
  public
    property Declared: Boolean read FDeclared;
    property Error: string read FError;
    property Active: Boolean read FActive;
    class function Load(const AAnchorDir: string): TOwnRoots; static;
    ...
  end;

class function TOwnRoots.Load(const AAnchorDir: string): TOwnRoots;
begin
  Result         := Default(TOwnRoots);
  Result.FActive := AAnchorDir <> '';          // <-- flagged as "never written"
  if not Result.FActive then Exit;
  ...
  Result.FDeclared:= Length(Result.FRoots) > 0; // <-- flagged as "never written"
  ...
  Result.FError:= Format('...');                // <-- flagged as "never written"
end;
```

`FDeclared`/`FError`/`FActive` are each read via a public property elsewhere in
the same unit (`IsOurs`, and any external caller through the properties), and
are demonstrably written above -- the whole point of `Load` returning a
populated `TOwnRoots`. A caller of `Load` genuinely observes non-default
values for all three fields (verified via `selftest own-roots`, which asserts
`Own.Declared`, `Own.Error`, `Own.Active` behaviour end-to-end and passes).

## Expected vs actual

- **Expected:** no `referenced-never-set` finding for `FDeclared`/`FError`/
  `FActive` -- each is written inside `Load` before `Load` returns, and the
  writes are on the very value (`Result`) the function hands back to every
  caller.
- **Actual:** all three are flagged as "read but never written", because the
  write side of the def-use pass never credits the assignment to the field at
  all.

## Root cause

`src\diagnostics\DRagLint.Diagnostics.DeadCodeChecks.pas:1786`,
`LhsBaseIdent` (called from `ClassifyRefs`'s `assignment` handling at
line 1838-1848): given an `assignment` node's `lhs`, it repeatedly walks
`ChildByField('lhs')` / `ChildByField('entity')` / "first named child" until
it reaches a plain `identifier` node, and returns THAT identifier's lowercased
name as the field being written:

```pascal
function LhsBaseIdent(const ALhsNode: TTSNode): string;
begin
  ...
  repeat
    if Cur.NodeType = 'identifier' then
    begin
      Result:= LowerCase(Trim(NodeStr(Cur)));
      Exit;
    end;
    Nxt:= Cur.ChildByField('lhs');
    if Nxt.IsNull then Nxt:= Cur.ChildByField('entity');
    ...
    Cur:= Nxt;
  until Cur.IsNull;
end;
```

For `FField.Sub := X` (the shape the comment at line 1783 says this function
is meant to handle) this correctly peels down to `FField`. But for
`Result.FField := X` inside a `class function ... : TSomeRecordType`, the
dotted expression's own leftmost identifier is `Result`, not `FField` --
`LhsBaseIdent` returns `"result"`. `ClassifyRefs` then checks
`AFields.ContainsKey(BaseName)` (`DeadCodeChecks.pas:1844`); `"result"` is
never a class/record field name, so the write is silently dropped instead of
being credited to `FField`. The field keeps 1+ reads (via its property
getter) and 0 recorded writes, so `CheckReferencedNeverSet`
(`DeadCodeChecks.pas:2080`) fires.

This will recur for **any** record- or class-factory method that assigns
through `Result.<field> := ...` (a common Delphi idiom for value-type
"named constructor" patterns, and for classes whose constructor logic lives
in a class function rather than `Create`) -- not specific to this one unit.

## Suggested fix direction (not attempted -- out of scope for Task 4)

`LhsBaseIdent`'s peeling should special-case a leading `Result`/`Self`
identifier on a dotted LHS: when the leftmost identifier is `Result` (inside
a function/class function) or `Self`, continue peeling into the RIGHT side of
that first dot (i.e. treat `Result.FField` as if the base were `FField`, the
same way `Self.FField := X` already resolves correctly by naturally landing
on `FField` when `Self` is elided). Confirmed only via manual reasoning over
the source, not by patching and re-testing (out of this task's scope).
