unit thrOrder2;

{ Fixture of tests\autotest\run_v156_THR-R.ps1 (1.56 lane THR-R): the other half of the cross-unit
  case. thrOrder.GlobalXY takes GLockX then GLockY; GlobalYX here takes them in the opposite order. }

interface

uses
  System.SyncObjs
, thrOrder
  ;

/// <summary>Takes the two unit-level locks of thrOrder Y then X.</summary>
procedure GlobalYX;

implementation

procedure GlobalYX;
begin
  GLockY.Enter;
  try
    GLockX.Enter; // HIT-GLOBAL-YX
    GLockX.Leave;
  finally
    GLockY.Leave;
  end;
end;

end.
