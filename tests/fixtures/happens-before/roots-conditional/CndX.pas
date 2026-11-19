unit CndX;

interface

uses
  {$IFDEF HB_ROOTS_FOO} CndZ, {$ENDIF}
  CndW;

implementation

var
  GX: Integer;

initialization
  GX:= 1;
end.