unit main;
interface
{$I config.inc}
{$IFDEF FEATURE_X}
const HasX = True;
{$ELSE}
const HasX = False;
{$ENDIF}
implementation
end.
