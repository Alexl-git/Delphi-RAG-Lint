unit sdHooks;

interface

type
  THookProc = procedure;

var
  GInd: Integer;
  GDir: Integer;
  GHook: THookProc;

procedure SetBoth;
procedure UseViaHook;
procedure UseDirect;

implementation

procedure SetBoth;
begin
  GInd:= 1;
  GDir:= 1;
end;

procedure UseViaHook;
begin
  Writeln(GInd); // USE-INDIRECT
end;

procedure UseDirect;
begin
  Writeln(GDir); // USE-DIRECT
end;

end.
