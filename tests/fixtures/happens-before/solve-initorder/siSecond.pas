unit siSecond;

{ check-init fixture solve-initorder (lane HBSOLVER): reads siFirst.GCfg directly and through a call. }

interface

var
  GLocal: Integer;
  GOther: Integer;

implementation

uses
  siFirst;

initialization
  GLocal:= siFirst.GCfg; // USE-DIRECT
  GOther:= ReadCfg; // USE-VIA-CALL
end.
