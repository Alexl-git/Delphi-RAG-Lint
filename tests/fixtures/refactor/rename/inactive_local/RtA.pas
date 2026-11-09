unit RtA;

interface

var
  Glob: Integer;

function Go(Val: Integer): Integer;

implementation

function Go(Val: Integer): Integer;
var
  Tmp: Integer;
begin
  Tmp:= Val + 1;
  {$IFDEF NEVER_DEFINED}
  Tmp:= Tmp + 2;
  {$ENDIF}
  Result:= Tmp;
end;

function Go2: Integer;
begin
  {$IFDEF NEVER_DEFINED}
  Glob:= 1;
  {$ENDIF}
  Result:= Glob;
end;

end.
