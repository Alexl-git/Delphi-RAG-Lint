> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21). FIXED -- but NOT by the mechanism this note names.** The note says an array local is *"never counted as defined"*. It is: definite-assignment uses `AssignmentBaseIndex`, so `A[i] := x` does define `A`. The real cause was `IsManagedType`, which tested for the substring `'array of'` -- matching a DYNAMIC array but not `array[0..2] of string`, because the range sits between the two words. A static array of a managed element type was therefore treated as unmanaged and reported, though the compiler zero-initialises it exactly as it does a bare `string` local. `IsManagedType` now recurses on the element type. DataCopy `used-before-assignment` **3 -> 0**; `array[0..2] of Integer` still reported (not zero-initialised on the stack). Guarded by `tests\autotest\run_used_before_assignment_arrays.ps1` (3/3).

# `used-before-assignment`: `@Arr[0]` handed to a filling API is not counted as a write

Class: **wrong**. **2 findings** (YADFOT `YADFOT.Wizard.pas` 243 and 247).
Split out of `INBOX-used-before-assignment-out-arg-in-large-routine.md` on
2026-08-14 once the dangling-else defect was fixed and these did not go away.

> **THIS NOTE'S FIRST VERSION WAS WRONG AND IS CORRECTED BELOW.** It claimed the
> defect was "an array local is never counted as defined", covering 5 findings
> across two projects. A 5-case probe refuted both halves: element-wise
> assignment IS tracked, and the 3 DataCopy findings are a different thing
> entirely. Written down because the first version was filed from a pattern match
> on the source rather than from a probe -- the same mistake the dangling-else
> note cost three sessions.

## What the probe established

`docs\probe-used-before-assignment-array.pas` (5 cases, bare `lint <file>`):

| case | shape | fires |
|---|---|---|
| A1 | `Arr[I] := I` in a `for`, summed in a later `for` | no |
| A2 | `Arr[0] := 1; Arr[1] := 2;` straight-line, then read | no |
| A3 | `GetModuleFileNameA(0, @Buf[0], Length(Buf))`, then read `Buf[0]` | **YES** warn |
| A4 | `SetLength(Dyn, 3)`, `Dyn[I] := I` in a `for`, then read | no |
| A5 | never assigned at all -- the positive control | **YES** warn (correct) |

**So element-wise assignment is tracked correctly, in a loop and straight-line,
static and dynamic.** The only broken form is the ADDRESS-OF one.

## The actual defect

```pascal
var
  Chunk: array[0..ChunkSize - 1] of AnsiChar;
begin
  ...
    Got := Reader.GetText(Pos, @Chunk[0], ChunkSize);   { <-- 243, flagged }
    if Got > 0 then
    begin
      Move(Chunk[0], Utf8Bytes[CurLen], Got);           { <-- 247, flagged }
```

`GetText` fills the buffer through the pointer, so **line 243 is a WRITE** --
`dl:ok` there would record something untrue, same as the dangling-else case.
Taking the address of a variable and passing it to a call is at minimum a
POSSIBLE definition and is conventionally a definite one; today it counts as a
read and as nothing else, so 247's read has no reaching definition either.

## Fix

`CollectReadsAndCallDefs` already has possible-def machinery for `out`
arguments. `@X` in an argument position belongs in it: treat `@` applied to any
lvalue as a def of the base variable, conservatively and unconditionally. There
is no shape where taking a variable's address and passing it somewhere should
leave that variable "definitely unassigned" -- the callee is the only thing that
knows, and the analysis cannot see it.

Check `var`/`out` ARRAY parameters have no separate hole while in there; the two
sites above do not cover that.

## What the DataCopy findings actually are -- NOT this bug

`uZeissRoutines.pas` 1160 and 1229 (x2), on `LRestore` / `LBackup`, are
**correlated conditions**, and the rule is arguably right:

```pascal
1138  LHasBck := LPresent[0] and ... ;
1139  if LHasBck then
1140  begin
1149    LRestore[LJdx] := Format(...);      { assigned ONLY when LHasBck }
1152  end;
1158  if LHasBck then
1160    if FileExists(LRestore[LJdx]) then  { read, guarded by the SAME flag }
```

Write and read are each guarded by `LHasBck`, so the code is correct -- but a
path-INSENSITIVE dataflow analysis cannot know the two guards are the same
condition, and the honest answer on the CFG is "may be unassigned here". That is
exactly what it reports, at `info` severity with the word "may".

**So these are a known limitation, not a defect, and they will not be fixed by
the `@` change above.** They are legitimate `dl:ok` candidates (unlike the
address-of ones): the flagged line really is a read, and the reviewer really is
asserting something the analyser cannot see. Path-sensitive correlated-condition
tracking is a large piece of work and not obviously worth it; note it and move on.

## Reproduce

```
drag-lint lint docs\probe-used-before-assignment-array.pas
drag-lint lint-all --project C:\Projects\YADF\YADFOT.dproj
```
