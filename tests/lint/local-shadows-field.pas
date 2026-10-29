unit local_shadows_field;

{ Fixture for local-shadows-field (OFF by default, info).
  Hit: a local var (or inline var) of a method whose name equals a field of
  the method's own class (or an ancestor declared in the same file).
  FP shapes kept silent: a local that merely resembles the field
  (FCount vs Count), a same-named local in a free routine, a same-named local
  in a method of an unrelated class, a field accessed qualified (Self.Count)
  with no local of that name. }

interface

type
  TBase = class
  protected
    Total: Integer;
  end;

  TFoo = class(TBase)
  private
    Count: Integer;
    Name: string;
  public
    procedure Hit;
    procedure HitInherited;
    procedure HitInline;
    procedure NoHitDifferentName;
    procedure NoHitQualified;
    procedure HitParam(Count: Integer);
    procedure NoHitParam(Cnt: Integer);
  end;

  TOther = class
  public
    procedure NoHitOtherClass;
  end;

implementation

procedure TFoo.Hit;
var
  Count: Integer;
begin
  Count:= 1;
end;

procedure TFoo.HitInherited;
var
  Total: Integer;
begin
  Total:= 1;
end;

procedure TFoo.HitInline;
begin
  var Name: string:= 'x';
  Writeln(Name);
end;

procedure TFoo.NoHitDifferentName;
var
  Cnt: Integer;
begin
  Cnt:= Count;
end;

procedure TFoo.NoHitQualified;
begin
  Self.Count:= 2;
end;

procedure TOther.NoHitOtherClass;
var
  Count: Integer;
begin
  Count:= 1;
end;

procedure FreeRoutine;
var
  Count: Integer;
begin
  Count:= 1;
end;
procedure TFoo.HitParam(Count: Integer);
begin
  Writeln(Count);
end;

procedure TFoo.NoHitParam(Cnt: Integer);
begin
  Writeln(Cnt);
end;

end.