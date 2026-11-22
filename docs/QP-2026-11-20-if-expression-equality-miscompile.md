<!-- dl:backlog status=open last-measured=2026-11-20 -->
# QP candidate: comparing two if-expressions inside an `if` statement answers False for equal strings

Status: reproduced 2026-11-20 (lane v1523 LSP-PROXY, item FINISHSRV-MISCOMPILE). Not filed yet --
owner files Embarcadero Quality Portal reports. Affects DRagLint only where the shape is written;
the one known site (`TProxyMergeEngine.FinishServerFrame`, 1.52.2) already compares locals.

## Compiler

RAD Studio 37.0 (Delphi 13 Florence). Reproduced with dcc64 (`-$D+ -$O-` and `-$D- -$O+`) and dcc32
(`-$D+ -$O-`). Not a debug-only or a Win64-only defect.

## Minimal repro

```pascal
program IfExprEq;
{$APPTYPE CONSOLE}
uses System.SysUtils;

function Has(const S: string): Boolean;
begin
  Result:= S <> '';
end;

{ the comparison as an if-statement condition: WRONG }
function V2(const A, B: string): Boolean;
begin
  if (if Has(A) then A else '') = (if Has(B) then B else '') then Exit(True);
  Result:= False;
end;

{ the same comparison assigned to a Boolean: right }
function V1(const A, B: string): Boolean;
begin
  Result:= (if Has(A) then A else '') = (if Has(B) then B else '');
end;

var
  P: string;
begin
  P:= 'alpha';
  Writeln('V1 ', V1(P, P));   { TRUE  (expected TRUE) }
  Writeln('V2 ', V2(P, P));   { FALSE (expected TRUE) }
end.
```

`dcc64 -CC -NSSystem IfExprEq.dpr`, then run.

## Measured

| shape | dcc64 Debug | dcc64 Release | dcc32 Debug |
|---|---|---|---|
| `Result:= (if ..) = (if ..)` | right | right | right |
| `B:= (if ..) = (if ..)` (Boolean local) | right | right | right |
| `Result:= if (if ..) = (if ..) then 'eq' else 'ne'` | right | right | right |
| `if (if ..) = (if ..) then` -- same string instance on both sides | **False** | **False** | **False** |
| `if (if ..) = (if ..) then` -- equal content, two instances | **False** | **False** | **False** |
| `if (if ..) = (if ..) then` -- both '' | right | right | **False** |
| `if (if ..) = (if ..) then` -- different strings | right (False) | right (False) | right (False) |
| same inside try..finally, inside a method on a field | **wrong** | **wrong** | **wrong** |

So: an equality of two string if-expressions used DIRECTLY as an `if`-statement condition evaluates
False even when both sides are the same string. Assigning the comparison first is correct.

Note: the 1.52.2 code comment in `DRagLint.LSP.Proxy.Merge.pas` (FinishServerFrame) says the direct
form "answered equal". The measurement is the opposite (answers NOT equal for equal sets); the
work-around (compare locals) is right either way.

## Not reproduced

`dcc64 F2084` on an if-expression inside an array constructor (TableTools lane note, 1.52): 17
shapes tried (TArray<string|Integer|Int64|Boolean|TObject|Variant>, open array of const in Format,
VarArrayOf, nested if-expression, concatenation, set constructor, `A:= A + [..]`) all compile
(an 18th, TArray<TBytes>, stopped at an ordinary E2010 in the probe itself).
The original source line was not recorded; re-open with the exact line if it recurs.

## Work-around

Assign each if-expression to a local (or the comparison to a Boolean) before the `if`.
