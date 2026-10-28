unit UbaMemberWrite;

{ used-before-assignment on a member WRITE through a never-assigned CLASS local,
  linted WITHOUT a symbol store (`lint <file>`, the IDE / fixture path).
  With a store, FlowChecks asks ResolveTypeCategory (ef4ba821,
  tests\autotest\run_uba_class_local_deref_write.ps1). Without one, only a
  class the SAME unit declares can be classified -- a type from another unit
  stays silent, because a `T` prefix names records and classes alike. }

interface

implementation

type
  TFoo = class
    K: Integer;
  end;
  TRec = record
    K: Integer;
  end;

procedure ClassWrite;
var Obj: TFoo;
begin
  Obj.K := 1;
end;

procedure RecordWrite;
var R: TRec;
begin
  R.K := 1;
end;

procedure AssignedFirst;
var Obj: TFoo;
begin
  Obj := TFoo.Create;
  Obj.K := 1;
  Obj.Free;
end;

procedure OneBranch(pFlag: Boolean);
var Obj: TFoo;
begin
  if pFlag then
    Obj := TFoo.Create;
  Obj.K := 1;
end;

procedure WithWrite;
var Obj: TFoo;
begin
  with Obj do
    K := 1;
end;

procedure ForeignType;
var S: TStringList;
begin
  S.Sorted := True;
end;

end.
