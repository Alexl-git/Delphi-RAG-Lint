unit State;

interface

type
  TSt = class
  private
    FSeen: Boolean;          // conditional write behind begin: state, stays silent
    FSeen2: Boolean;         // conditional write behind then: state, stays silent
    FCount: Integer;         // X := X + 1 reads before it writes, stays silent
    FOk: Integer;            // FIRE field-could-be-local
    FKeys: Variant;          // read from another routine through an argument, stays silent
  public
    procedure Tick(Go: Boolean);
    procedure Acc;
    procedure Plain;
    procedure Pick;
    procedure Drop(I: Integer);
  end;

procedure Take(const V: Variant);

implementation

procedure Take(const V: Variant);
begin
end;

procedure TSt.Tick(Go: Boolean);
begin
  if Go then
  begin
    FSeen:= True;
  end;
  if FSeen then Writeln('seen');
  if Go then FSeen2:= True;
  if FSeen2 then Writeln('seen2');
end;

procedure TSt.Acc;
begin
  FCount:= FCount + 1;
  Writeln(FCount);
end;

procedure TSt.Plain;
begin
  FOk:= 7;
  Writeln(FOk);
end;

procedure TSt.Pick;
begin
  FKeys:= VarArrayCreate([0, 1], varVariant);
  FKeys[0]:= 1;
end;

procedure TSt.Drop(I: Integer);
begin
  Take(FKeys[I]);
end;

end.