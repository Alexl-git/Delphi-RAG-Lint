unit uLeafDecl;

{ `Child` is declared exactly ONCE as a method, so the old call-target-only
  ambiguity test called it unambiguous -- while uLeafUse below binds the same
  name as a routine local several times over. `Anchor` is the positive control:
  a uniquely named method WITH a real resolved caller, whose Called from: list
  must survive. }

interface

type
  TWalker = class
    function Child(AIndex: Integer): Integer;
    function Anchor(AIndex: Integer): Integer;
  end;

procedure DriveAnchor;

implementation

function TWalker.Child(AIndex: Integer): Integer;
begin
  Result := AIndex;
end;

function TWalker.Anchor(AIndex: Integer): Integer;
begin
  Result := AIndex;
end;

procedure DriveAnchor;
var
  W: TWalker;
begin
  W := TWalker.Create;
  W.Anchor(1);
end;

end.
