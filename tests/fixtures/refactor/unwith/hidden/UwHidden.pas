unit UwHidden;

{ Deliberately NOT a member of UwDemo.dproj / .dpr. The search path names it through $(UW_HIDDEN), which the guard sets
  for the builds and not for the index: so the index never sees it, and THiddenBase is an unresolved ancestor whose
  member Secret the closure cannot know. }

interface

type
  THiddenBase = class
  public
    Secret: Integer;
    constructor Create;
  end;

implementation

constructor THiddenBase.Create;
begin
  inherited Create;
  Secret:= 77;
end;

end.