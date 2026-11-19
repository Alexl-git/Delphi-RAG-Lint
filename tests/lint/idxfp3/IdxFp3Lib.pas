unit IdxFp3Lib;

{ Fixture for run_v152_IDXRANGE3.ps1: a routine of ANOTHER unit that sizes its Result by a
  parameter (YADF.LineScan.ComputeBlockCommentLock), read from the index by lint --db. }

interface

uses
  System.Classes;

function LibLock(ALines: TStringList): TArray<Boolean>;
function LibLockShort(ALines: TStringList): TArray<Boolean>;

implementation

function LibLock(ALines: TStringList): TArray<Boolean>;
var
  i: Integer;
begin
  SetLength(Result, ALines.Count);
  for i:= 0 to ALines.Count - 1 do Result[i]:= ALines[i] = '';
end;

function LibLockShort(ALines: TStringList): TArray<Boolean>;
var
  i: Integer;
begin
  SetLength(Result, ALines.Count - 1);
  for i:= 0 to ALines.Count - 2 do Result[i]:= ALines[i] = '';
end;

end.
