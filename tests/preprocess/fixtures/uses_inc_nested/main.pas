unit main;
interface
{$I outer.inc}
{$IFDEF NESTED_OK}
const Nested = True;
{$ELSE}
const Nested = False;
{$ENDIF}
implementation
end.
