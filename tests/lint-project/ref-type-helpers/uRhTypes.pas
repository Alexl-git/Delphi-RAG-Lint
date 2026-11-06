unit uRhTypes;

{ Fixture of run_ref_type_helpers.ps1: the ancestry and the expressions the harness asks about.
  Stand-in classes only, so the fixture needs no library index. }

interface

type
  TRhBase = class
  end;

  TRhMid = class(TRhBase)
  end;

  TRhLeaf = class(TRhMid)
  end;

  TRhOther = class
  end;

  { Derives from a class this project does not declare: its ancestry cannot be followed to the end. }
  TRhLibKid = class(TRhNowhere)
  end;

  TRhHolder = class
  public
    FLeaf: TRhLeaf;
    function Make(N: Integer): TRhMid;
    function Names: TRhHolder;
  end;

procedure RhUse(X: TRhLeaf);
procedure RhProbe;

implementation

procedure RhUse(X: TRhLeaf);
begin
  Assert(X <> nil);
end;

function TRhHolder.Make(N: Integer): TRhMid;
begin
  Result:= nil;
end;

function TRhHolder.Names: TRhHolder;
begin
  Result:= Self;
end;

procedure RhProbe;
var
  H : TRhHolder;
  M : TRhMid;
  Q : TRhLeaf;
begin
  H:= TRhHolder.Create;
  M:= H.FLeaf;
  M:= H.Make(1);
  M:= H.Names().FLeaf;
  M:= H.Names().Make(2);
  RhUse(Q);
  Zip.Zap:= 1;
end;

end.
