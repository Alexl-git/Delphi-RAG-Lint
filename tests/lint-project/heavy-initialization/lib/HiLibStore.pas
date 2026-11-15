unit HiLibStore;

{ Library fixture for heavy-initialization: a class whose method reaches the registry through a
  routine of its own unit. A project calls Load on a VARIABLE, so only the index's library
  binding (refs.external_target) names the target; the receiver text alone names nothing. }

interface

type
  THiLibStore = class
  public
    procedure Load;
  end;

  { Stands in for a heavy RTL type: a member of a type with this name counts as registry work
    by the name of its owner, whatever its body holds. }
  TRegistry = class
  public
    procedure OpenKey;
  end;

{ The shared registry object: a project reaches TRegistry.OpenKey without naming the type. }
function HiLibReg: TRegistry;

implementation

uses
  HiLibUnit;

procedure THiLibStore.Load;
begin
  HiLibReadSettings;
end;

procedure TRegistry.OpenKey;
begin
end;

function HiLibReg: TRegistry;
begin
  Result:= nil;
end;

end.
