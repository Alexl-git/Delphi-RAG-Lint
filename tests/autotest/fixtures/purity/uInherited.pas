unit uInherited;
{ Purity v2 stage fixture: a bare `inherited;` is a STATIC call to the
  ancestor's implementation. Ancestor outside this DB -> ? (acceptance 20);
  ancestor inside -> judged by that method's own summary (the two controls). }
interface
type
  TInDb = class
  public
    procedure Run; virtual;
    procedure Quiet; virtual;
  end;
  TChildInDb = class(TInDb)
  public
    procedure Run; override;       { inherited -> TInDb.Run writes a global -> g }
    procedure Quiet; override;     { inherited -> TInDb.Quiet is proven -> proven }
  end;
  TChildOutside = class(TObject)
  public
    procedure AfterConstruction; override;   { inherited -> TObject is not in this DB -> ? }
  end;
var
  GRuns: Integer;
implementation
procedure TInDb.Run;
begin
  GRuns := GRuns + 1;
end;
procedure TInDb.Quiet;
begin
end;
procedure TChildInDb.Run;
begin
  inherited;
end;
procedure TChildInDb.Quiet;
begin
  inherited;
end;
procedure TChildOutside.AfterConstruction;
begin
  inherited;
end;
end.
