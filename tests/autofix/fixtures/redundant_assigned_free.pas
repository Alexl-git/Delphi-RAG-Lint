unit redundant_assigned_free;

interface

uses
  System.Classes, System.SysUtils;

implementation

procedure Demo;
var
  Obj: TObject;
  Authenticated: Boolean;
begin
  Obj := TObject.Create;
  if Assigned(Obj) then Obj.Free;
  Authenticated := True;
  if Authenticated then Obj := nil;
end;

end.
