unit VerifyMain;

{ Fixture for run_verify_index_guard.ps1: cross-unit references into VerifyLib. }

interface

procedure RunAll;

implementation

uses
  VerifyLib;

procedure RunAll;
var
  T: TLibThing;
  N: Integer;
begin
  LibProc;
  N:= LibConst;
  T:= TLibThing.Create;
  try
    T.Go;
    N:= T.Twice(N);
    LibProc;
  finally
    T.Free;
  end;
end;

end.