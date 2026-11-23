unit BvUse;

interface

function CountRuns(const A: TArray<string>): Integer;
function CtlCountRuns(const A: TArray<string>): Integer;

implementation

uses
  BvLib;

{ silent: ReportAt takes the index by value (PurityStage:1221 BeatProgress(I)); J, which starts at I, stays in range }
function CountRuns(const A: TArray<string>): Integer;
var
  I, J: Integer;
begin
  Result := 0;
  I := 0;
  while I <= High(A) do
  begin
    ReportAt(I, A[I]);
    J := I;
    while (J <= High(A)) and (A[J] = A[I]) do Inc(J);
    ReportAt(J, '');
    Inc(Result);
    I := J;
  end;
end;

{ control: MoveOn may write the index }
function CtlCountRuns(const A: TArray<string>): Integer;
var
  I, J: Integer;
begin
  Result := 0;
  I := 0;
  while I <= High(A) do
  begin
    J := I;
    while (J <= High(A)) and (A[J] = A[I]) do Inc(J);
    MoveOn(J);
    Inc(Result);
    I := J;
  end;
end;

end.
