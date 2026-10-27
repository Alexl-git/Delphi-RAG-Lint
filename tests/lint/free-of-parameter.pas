unit free_of_parameter;

{ Fixture for free-of-parameter (warning).
  Hit: P.Free / FreeAndNil(P) / P.DisposeOf where P is a by-value or const
  parameter of the enclosing routine: the caller's reference now dangles.
  Silent: a var / out parameter, a local variable, a field, a parameter of a
  different routine. }

interface

uses
  System.Classes;

procedure HitFree(AObj: TObject);
procedure HitFreeAndNil(AObj: TObject);
procedure HitDispose(const AObj: TObject);
procedure NoHitVar(var AObj: TObject);
procedure NoHitLocal(AObj: TObject);

implementation

procedure HitFree(AObj: TObject);
begin
  AObj.Free;
end;

procedure HitFreeAndNil(AObj: TObject);
begin
  FreeAndNil(AObj);
end;

procedure HitDispose(const AObj: TObject);
begin
  AObj.DisposeOf;
end;

procedure NoHitVar(var AObj: TObject);
begin
  FreeAndNil(AObj);
end;

procedure NoHitLocal(AObj: TObject);
var
  Tmp: TObject;
begin
  Tmp:= TObject.Create;
  Tmp.Free;
  AObj.ToString;
end;

end.
