{$IFDEF COMPILE1}
var
  X: Integer;
type
  TShape = Integer;
{$ELSE}
var
  X: Double;
type
  TShape = Double;
{$ENDIF}