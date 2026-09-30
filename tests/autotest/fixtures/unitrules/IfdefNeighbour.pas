unit IfdefNeighbour;

interface

uses
  KeepU {$IFDEF FOO}, OtherU{$ENDIF}, OldU;

implementation

end.