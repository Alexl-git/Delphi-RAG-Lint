unit VerifyLib;

{ Fixture for run_verify_index_guard.ps1: the declarations VerifyMain resolves to. }

interface

const
  LibConst = 3;

type
  TLibThing = class
  public
    procedure Go;
    function Twice(AValue: Integer): Integer;
  end;

procedure LibProc;

implementation

procedure LibProc;
begin
end;

procedure TLibThing.Go;
begin
end;

function TLibThing.Twice(AValue: Integer): Integer;
begin
  Result:= AValue * 2;
end;

end.