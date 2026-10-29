unit MagicComments;

interface

implementation

uses SysUtils;

procedure Bad;
begin
  // TODO: finish this
  raise ENotImplemented.Create('later');    // HIT: todo-left merge, an unfinished-work marker
end;

procedure Good;
begin
  // DEBUG_MODE only, not a work item
  raise EArgumentException.Create('bad');   // NOT: an ordinary exception
end;

end.
