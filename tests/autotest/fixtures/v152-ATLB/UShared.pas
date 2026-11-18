unit UShared;   // dl:shared PROJA, PROJB

{ A unit compiled by two projects. Only project PROJA's index is open in the
  run, and inside it SharedProc is referenced from this unit alone -- project
  PROJB may call it, so the rule must stay silent here. The runner's control
  copy drops the marker, and then the line below MUST be reported. }

interface

type
  TShared = class
  public
    procedure SharedProc; { (-) }
    procedure Run;
  end;

implementation

procedure TShared.SharedProc;
begin
end;

procedure TShared.Run;
begin
  SharedProc;
end;

end.
