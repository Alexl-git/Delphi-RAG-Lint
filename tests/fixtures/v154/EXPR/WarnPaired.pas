unit WarnPaired;

interface

implementation

{$WARNINGS OFF}
procedure P;
begin
  Exit;
end;
{$WARNINGS ON}

{$IFDEF FOO}
{$WARNINGS OFF}
{$ELSE}
{$WARNINGS ON}
{$ENDIF}

(*$WARNINGS OFF*)
procedure Q;
begin
  Exit;
end;
(*$WARNINGS ON*)

end.
