unit siFirst;

{ check-init fixture solve-initorder (lane HBSOLVER). Listed FIRST in SolveInitOrder.dpr: through the
  uses cycle siSecond initializes BEFORE this unit, so its reads see GCfg = 0. In the -swapped twin the
  .dpr lists siSecond first and this unit initializes first. }

interface

var
  GCfg: Integer;

function ReadCfg: Integer;

implementation

uses
  siSecond;

function ReadCfg: Integer;
begin
  Result:= GCfg; // USE-CALL
end;

initialization
  GCfg:= 7; // WRITER
end.
