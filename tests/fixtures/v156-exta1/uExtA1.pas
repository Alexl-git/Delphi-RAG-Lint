unit uExtA1;

{ Fixture of tests\autotest\run_v156_EXTA1_facts.ps1 (1.56 lane EXT-A1): B1 noreturn, B2 variant
  part, B8 parameter mode, C-1 call literal arguments. Index-only: it need not compile. }

interface

type
  TKind = (kA, kB);

  TShape = record
    Id: Integer;
    case Kind: TKind of
      kA: (Width, Height: Double);
      kB: (Radius: Double;
           case Byte of
             0: (Inner: Integer);
             1: (Outer: Word));
  end;

  TPlain = record
    A: Integer;
  end;

  TWorker = class
  public
    procedure Stop(const AWhy: string); noreturn;
    procedure Go(var ACount: Integer);
  end;

procedure Fail(const AText: string); noreturn;
procedure Modes(AVal: Integer; const AConst: string; var AVar: Integer; out AOut: Integer; const [Ref] ARef: TShape; [Ref] const ARef2: TShape);
function Plain(X, Y: Integer): Integer;
procedure Abort;

implementation

const
  FLD_NAME = 'NAME';

procedure Fail(const AText: string);
begin
  raise Exception.Create(AText);
end;

procedure Modes(AVal: Integer; const AConst: string; var AVar: Integer; out AOut: Integer; const [Ref] ARef: TShape; [Ref] const ARef2: TShape);
begin
  AOut:= AVal;
end;

function Plain(X, Y: Integer): Integer;
begin
  Result:= X + Y;
end;

procedure Abort;
begin
end;

procedure TWorker.Stop(const AWhy: string);
begin
  Fail(AWhy);
end;

procedure TWorker.Go(var ACount: Integer);
begin
  Inc(ACount);
end;

procedure UseCalls(DS: TDataSet);
var
  Local: string;
begin
  DS.FieldByName('CODE').AsString:= Local;
  DS.FieldByName(FLD_NAME).Clear;
  DS.FieldByName(Local).Clear;
  DS.Locate('A;B', 5, []);
  Plain(1,
    -2);
  DS.FieldValues['QTY']:= Plain(X, Y);
  DS.Fields[0].Clear;
  Local:= Format('%s''s', [Local]);
  Other.SetKind(TKind.kB, Local);
end;

end.
